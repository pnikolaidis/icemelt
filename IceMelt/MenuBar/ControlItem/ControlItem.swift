//
//  ControlItem.swift
//  IceMelt
//

import Cocoa
import Combine

// MARK: - ControlItem

/// A status item that controls a section in the menu bar.
@MainActor
final class ControlItem {
    /// An identifier for a control item.
    ///
    /// The raw values double as `NSStatusItem` autosave names, which macOS uses to
    /// persist each control item's position in the menu bar. They are frozen at their
    /// original "Ice" spelling — renaming them would scramble the placement of every
    /// existing user's control items.
    enum Identifier: String, CaseIterable {
        /// The identifier for the control item for the visible section.
        case visible = "Ice.ControlItem.Visible"
        /// The identifier for the control item for the hidden section.
        case hidden = "Ice.ControlItem.Hidden"
        /// The identifier for the control item for the always-hidden section.
        case alwaysHidden = "Ice.ControlItem.AlwaysHidden"

        /// A tag for the control item with this identifier.
        var tag: MenuBarItemTag {
            switch self {
            case .visible: .visibleControlItem
            case .hidden: .hiddenControlItem
            case .alwaysHidden: .alwaysHiddenControlItem
            }
        }

        /// Returns the length associated with this identifier and
        /// the given hiding state.
        func length(for state: HidingState) -> CGFloat {
            switch self {
            case .visible:
                Lengths.standard
            case .hidden, .alwaysHidden:
                switch state {
                case .showSection: Lengths.standard
                case .hideSection: Lengths.expanded
                }
            }
        }
    }

    /// The frames of the control items currently in the menu bar, in screen
    /// coordinates, keyed by identifier.
    ///
    /// As of macOS 27, the menu bar is hosted by `MenuBarAgent` and the control
    /// items' windows no longer report a meaningful position through the window
    /// server. Their AppKit frames still track the agent's layout, which is how
    /// hosted items are matched back to the control items (see
    /// ``MenuBarItem/getMenuBarItems(on:option:)``).
    private(set) static var hostedFrames = [Identifier: CGRect]()

    /// A hiding state for a control item.
    enum HidingState {
        case showSection
        case hideSection
    }

    /// A namespace for control item lengths.
    private enum Lengths {
        static let standard: CGFloat = NSStatusItem.variableLength

        /// The length of a section divider that is hiding its section, before
        /// macOS 27: an item this wide pushes everything to its left off the
        /// screen. On macOS 27 the length is measured instead; see
        /// `hostedHidingLengths`.
        static let expanded: CGFloat = 10_000

        /// The padding macOS 27 adds around a status item's length.
        static let hostedPadding: CGFloat = 16

        /// The most items a divider may use to hide its section on macOS 27,
        /// itself included. Four covers the widest display Apple sells with
        /// room to spare; the bound keeps a bad measurement from filling the
        /// menu bar with blank items.
        static let maxHidingItems = 4
    }

    /// Storage for a control item's underlying status item.
    private final class StatusItemStorage {
        let statusItem: NSStatusItem
        let constraint: NSLayoutConstraint?

        /// Creates a new storage instance.
        @MainActor
        init(controlItem: ControlItem) {
            ControlItemDefaults.preflightSetup(for: controlItem)

            self.statusItem = NSStatusBar.system.statusItem(withLength: 0)
            self.statusItem.autosaveName = controlItem.identifier.rawValue

            if let button = statusItem.button {
                // This could break in a new macOS release, but we need this constraint in order to
                // be able to hide the status item when the `ShowSectionDividers` setting is disabled.
                // A previous implementation used `statusItem.isVisible`, which was more robust, but
                // would completely remove the status item. With the current set of features, we use
                // the control item positions to determine the items in each section, so we need the
                // status item to be present if its section is enabled. The new solution is to remove
                // a constraint from the item's content view prevents it from having a length of zero.
                // Then, we set the length. FIXME: Find a replacement for this.
                if
                    let constraints = button.window?.contentView?.constraintsAffectingLayout(for: .horizontal),
                    let constraint = constraints.first(where: Predicates.controlItemConstraint(button: button))
                {
                    assert(constraints.filter(Predicates.controlItemConstraint(button: button)).count == 1)
                    self.constraint = constraint
                } else {
                    self.constraint = nil
                }

                button.target = controlItem
                button.action = #selector(controlItem.performAction)
                button.sendAction(on: [.leftMouseDown, .rightMouseUp])
            } else {
                self.constraint = nil
            }
        }

        deinit {
            removeStatusItem()
        }

        /// Removes the status item from the status bar.
        private func removeStatusItem() {
            // Removing the status item has the unwanted side effect of
            // deleting the preferred position. Cache and restore it.
            let autosaveName = statusItem.autosaveName as String
            let cached = ControlItemDefaults[.preferredPosition, autosaveName]
            NSStatusBar.system.removeStatusItem(statusItem)
            ControlItemDefaults[.preferredPosition, autosaveName] = cached
        }
    }

    /// The control item's hiding state (`@Published`).
    @Published var state = HidingState.hideSection

    /// The control item's window (`@Published`).
    @Published private(set) var window: NSWindow?

    /// The control item's frame (`@Published`).
    @Published private(set) var frame: CGRect?

    /// The control item's screen (`@Published`).
    @Published private(set) var screen: NSScreen?

    /// The control item's frame, if it is onscreen (`@Published`).
    @Published private(set) var onScreenFrame: CGRect?

    /// The control item's identifier.
    let identifier: Identifier

    /// Lazy storage for the control item's underlying status item.
    private lazy var storage = StatusItemStorage(controlItem: self)

    /// The shared app state.
    private weak var appState: AppState?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// The control item's underlying status item.
    private var statusItem: NSStatusItem {
        storage.statusItem
    }

    /// A horizontal constraint for the control item's content view.
    private var constraint: NSLayoutConstraint? {
        storage.constraint
    }

    /// The width the divider should have to hide its section on macOS 27,
    /// as last measured by the item manager.
    private var hostedHidingWidth: CGFloat?

    /// Blank status items that fill the room the divider can't cover on its
    /// own, on macOS 27. See ``hostedHidingLengths``.
    private var spacers = [NSStatusItem]()

    /// The lengths of the items that hide the section on macOS 27: the
    /// divider first, then one for each spacer beside it.
    ///
    /// macOS 27 hides an item only by overflowing it, so the section is
    /// hidden by filling the room between the application menu and the
    /// visible items, which the item manager measures (see
    /// `MenuBarItemManager.hostedHidingWidths`). The system discards an item
    /// wider than half its display, so on a wide display the divider alone
    /// falls short — a 3840pt display needs ~2900pt of filling and allows
    /// 1904pt per item. The shortfall is made up with blank spacer items,
    /// which fill the same room without being wider than the cap. The room is
    /// divided evenly, so no spacer is near the cap unless it has to be.
    /// Until a measurement exists, the divider takes the most it can; the
    /// first cache corrects it.
    private var hostedHidingLengths: [CGFloat] {
        let padding = Lengths.hostedPadding
        let screenWidth = (NSScreen.screenWithActiveMenuBar ?? NSScreen.main)?.frame.width ?? 1_000
        let cap = (screenWidth / 2).rounded(.down) - padding
        guard let width = hostedHidingWidth else {
            return [cap]
        }
        // Each item occupies its length plus the agent's padding.
        let slot = cap + padding
        let count = min(max(Int((width / slot).rounded(.up)), 1), Lengths.maxHidingItems)
        let length = min(max(width / CGFloat(count) - padding, 0), cap)
        return Array(repeating: length, count: count)
    }

    /// A Boolean value that indicates whether the control item serves as
    /// a divider between sections.
    var isSectionDivider: Bool {
        identifier != .visible
    }

    /// A Boolean value that indicates whether the control item is currently
    /// displayed in the menu bar.
    var isAddedToMenuBar: Bool {
        statusItem.isVisible
    }

    /// The corresponding section name for the control item.
    var sectionName: MenuBarSection.Name {
        switch identifier {
        case .visible: .visible
        case .hidden: .hidden
        case .alwaysHidden: .alwaysHidden
        }
    }

    /// Creates a control item with the given identifier.
    init(identifier: Identifier) {
        self.identifier = identifier
    }

    /// Performs the initial setup of the control item.
    func performSetup(with appState: AppState) {
        self.appState = appState
        configureCancellables()
    }

    /// Configures the internal observers for the control item.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        $state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusItem()
            }
            .store(in: &c)

        statusItem.publisher(for: \.isVisible)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isVisible in
                guard
                    let self,
                    let menuBarManager = appState?.menuBarManager,
                    let section = menuBarManager.section(withName: sectionName),
                    let hotkey = section.hotkey
                else {
                    return
                }
                if isVisible {
                    hotkey.enable()
                } else {
                    hotkey.disable()
                }
            }
            .store(in: &c)

        statusItem.publisher(for: \.button).removeNil()
            .flatMap { $0.publisher(for: \.window) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] window in
                self?.window = window
            }
            .store(in: &c)

        $window.removeNil()
            .flatMap { $0.publisher(for: \.frame) }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frame in
                self?.frame = frame
                self?.updateHostedFrame(frame)
            }
            .store(in: &c)

        if let appState, isSectionDivider, #available(macOS 27.0, *) {
            // The hiding length is measured by the item manager as it caches
            // (see `hostedHidingLength`).
            appState.itemManager.$hostedHidingWidths
                .map { [identifier] widths in widths[identifier] }
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] width in
                    self?.hostedHidingWidth = width
                    self?.updateStatusItem()
                }
                .store(in: &c)
        }

        $window.removeNil()
            .flatMap { $0.publisher(for: \.screen) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] screen in
                self?.screen = screen
            }
            .store(in: &c)

        $screen.removeNil()
            .flatMap { $0.publisher(for: \.frame) }
            .combineLatest($frame.removeNil())
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] screenFrame, frame in
                guard let self else {
                    return
                }
                if screenFrame.intersects(frame) {
                    onScreenFrame = frame
                } else {
                    onScreenFrame = nil
                }
            }
            .store(in: &c)

        if let appState {
            appState.$isDraggingMenuBarItem
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] isDragging in
                    guard let self else {
                        return
                    }
                    if isDragging {
                        updateStatusItem()
                    }
                }
                .store(in: &c)

            if identifier == .visible {
                appState.settings.general.$showIceMeltIcon
                    .combineLatest(statusItem.publisher(for: \.isVisible))
                    .removeDuplicates()
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] shouldShow, _ in
                        guard let self else {
                            return
                        }
                        if shouldShow {
                            addToMenuBar()
                        } else {
                            removeFromMenuBar()
                        }
                    }
                    .store(in: &c)

                appState.settings.general.$iceMeltIcon
                    .combineLatest(appState.settings.general.$customIceMeltIconIsTemplate)
                    .removeDuplicates()
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] _ in
                        self?.updateStatusItem()
                    }
                    .store(in: &c)
            }

            if identifier == .alwaysHidden {
                appState.settings.advanced.$enableAlwaysHiddenSection
                    .combineLatest(statusItem.publisher(for: \.isVisible))
                    .removeDuplicates()
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] shouldEnable, _ in
                        guard let self else {
                            return
                        }
                        if shouldEnable {
                            addToMenuBar()
                        } else {
                            removeFromMenuBar()
                        }
                    }
                    .store(in: &c)
            }

            if isSectionDivider {
                appState.settings.advanced.$sectionDividerStyle
                    .removeDuplicates()
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] _ in
                        self?.updateStatusItem()
                    }
                    .store(in: &c)
            }
        }

        cancellables = c
    }

    /// Records the control item's frame in ``hostedFrames``, converting from
    /// AppKit's flipped coordinates to screen coordinates.
    private func updateHostedFrame(_ frame: CGRect) {
        guard isAddedToMenuBar, let primaryScreen = NSScreen.screens.first else {
            Self.hostedFrames[identifier] = nil
            return
        }
        Self.hostedFrames[identifier] = CGRect(
            x: frame.minX,
            y: primaryScreen.frame.height - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    /// Updates the appearance of the status item using the current hiding state.
    private func updateStatusItem() {
        guard
            let appState,
            let button = statusItem.button
        else {
            return
        }

        button.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        button.title = ""
        button.image = nil

        switch identifier {
        case .visible:
            updateStatusItemVisibility(true)
            button.appearsDisabled = false

            let icon = appState.settings.general.iceMeltIcon

            // We can usually just create the image directly from the icon.
            var image = switch state {
            case .showSection: icon.visible.nsImage(for: appState)
            case .hideSection: icon.hidden.nsImage(for: appState)
            }

            if
                case .custom = icon.name,
                let originalImage = image
            {
                // Custom icons need to be resized to fit inside the button.
                let originalWidth = originalImage.size.width
                let originalHeight = originalImage.size.height
                let ratio = max(originalWidth / 25, originalHeight / 17)
                let newSize = CGSize(width: originalWidth / ratio, height: originalHeight / ratio)
                image = originalImage.resized(to: newSize)
            }

            button.image = image
        case .hidden, .alwaysHidden:
            switch state {
            case .showSection:
                switch appState.settings.advanced.sectionDividerStyle {
                case .noDivider:
                    updateStatusItemVisibility(false)
                    button.appearsDisabled = true
                    button.isHighlighted = false

                    if appState.isDraggingMenuBarItem && appState.settings.advanced.showAllSectionsOnUserDrag {
                        // We still want a subtle marker between sections.
                        button.title = "|"
                    }
                case .chevron:
                    updateStatusItemVisibility(true)
                    button.appearsDisabled = false

                    button.image = switch identifier {
                    case .hidden:
                        ControlItemImage.builtin(.chevronLarge).nsImage(for: appState)
                    case .alwaysHidden:
                        ControlItemImage.builtin(.chevronSmall).nsImage(for: appState)
                    case .visible: nil
                    }
                }
            case .hideSection:
                updateStatusItemVisibility(true)
                button.appearsDisabled = true
                button.isHighlighted = false
            }
        }
    }

    /// Updates the visibility of the status item.
    ///
    /// The hidden and always-hidden control items must always be present in
    /// the menu bar, as we use their positions to determine the items in each
    /// section. Setting `statusItem.isVisible` to `false` completely removes
    /// the item. Instead, we toggle the width constraint on the item's content
    /// view, update the item's length, then adjust the content size of the
    /// item's window if needed.
    private func updateStatusItemVisibility(_ isVisible: Bool) {
        guard let appState else {
            return
        }

        if #available(macOS 27.0, *), isSectionDivider, isVisible, state == .hideSection {
            constraint?.isActive = true
            let lengths = hostedHidingLengths
            statusItem.length = lengths[0]
            updateSpacers(lengths: Array(lengths.dropFirst()))
            return
        }

        if #available(macOS 27.0, *), isSectionDivider {
            updateSpacers(lengths: [])
        }

        if isVisible {
            constraint?.isActive = true
            statusItem.length = identifier.length(for: state)
        } else {
            let showOnDrag = appState.settings.advanced.showAllSectionsOnUserDrag
            let isDragging = appState.isDraggingMenuBarItem

            let shouldShow = showOnDrag && isDragging

            constraint?.isActive = false
            statusItem.length = shouldShow ? 3 : 0

            if let window {
                let size = withMutableCopy(of: window.frame.size) { $0.width = shouldShow ? 3 : 1 }
                window.setContentSize(size)
            }
        }
    }

    /// Returns the `NSStatusItem` autosave name for the spacer at the given
    /// index beside this divider.
    private func spacerAutosaveName(at index: Int) -> String {
        "\(identifier.rawValue).Spacer\(index)"
    }

    /// Matches the divider's spacer items to the given lengths, creating and
    /// removing them as needed.
    ///
    /// The spacers are blank, have no action, and are never matched to a
    /// control item, so `MenuBarItem.getMenuBarItems(on:option:)` skips them
    /// along with any other slot of ours that isn't a control item. They are
    /// removed rather than collapsed when the section is shown: a zero-length
    /// item still occupies the agent's padding, which would leave a gap.
    @available(macOS 27.0, *)
    private func updateSpacers(lengths: [CGFloat]) {
        while spacers.count > lengths.count {
            NSStatusBar.system.removeStatusItem(spacers.removeLast())
        }
        while spacers.count < lengths.count {
            // A spacer with no preferred position is placed at the leading end
            // of the bar, where it overflows at once and fills nothing, so
            // each one is created with a position of its own. macOS 27 honors
            // the preferred position of a *new* item, measured leftwards from
            // the trailing end, but on a layout of natural widths, which the
            // expanded divider is not part of: a spacer can land on either
            // side of the divider at first, and settles into the room being
            // filled as the measurement converges. Only the total width
            // filled decides whether the section hides.
            let autosaveName = spacerAutosaveName(at: spacers.count)
            let dividerPosition = ControlItemDefaults[.preferredPosition, identifier.rawValue] ?? 1
            ControlItemDefaults[.preferredPosition, autosaveName] = dividerPosition + CGFloat(spacers.count + 1)

            let spacer = NSStatusBar.system.statusItem(withLength: 0)
            spacer.autosaveName = autosaveName
            // An item whose button is never touched gets a zero-width slot.
            spacer.button?.title = ""
            spacer.button?.appearsDisabled = true
            spacers.append(spacer)
        }
        for (spacer, length) in zip(spacers, lengths) where spacer.length != length {
            spacer.length = length
        }
    }

    /// Adds the control item to the menu bar.
    private func addToMenuBar() {
        guard !isAddedToMenuBar else {
            return
        }
        statusItem.isVisible = true
    }

    /// Removes the control item from the menu bar.
    private func removeFromMenuBar() {
        guard isAddedToMenuBar else {
            return
        }
        // Setting `statusItem.isVisible` to `false` has the unwanted side
        // effect of deleting the preferred position. Cache and restore it.
        let autosaveName = statusItem.autosaveName as String
        let cached = ControlItemDefaults[.preferredPosition, autosaveName]
        statusItem.isVisible = false
        ControlItemDefaults[.preferredPosition, autosaveName] = cached
    }

    /// Performs the control item's action.
    @objc private func performAction() {
        guard
            let menuBarManager = appState?.menuBarManager,
            let event = NSApp.currentEvent
        else {
            return
        }

        switch event.type {
        case .leftMouseDown:
            let modifierFlags = NSEvent.modifierFlags

            // Running this from a Task seems to improve the visual
            // responsiveness of the status item's button.
            Task {
                if modifierFlags == .control {
                    showMenu()
                    return
                }

                if
                    modifierFlags == .option,
                    let section = menuBarManager.section(withName: .alwaysHidden),
                    section.isEnabled
                {
                    section.toggle()
                    return
                }

                if
                    let section = menuBarManager.section(withName: sectionName),
                    section.isEnabled
                {
                    section.toggle()
                }
            }
        case .rightMouseUp:
            showMenu()
        default:
            return
        }
    }

    /// Creates a menu to show under the control item.
    private func createMenu(with appState: AppState) -> NSMenu {
        func hotkey(withAction action: HotkeyAction) -> Hotkey? {
            appState.settings.hotkeys.hotkey(withAction: action)
        }

        let menu = NSMenu(title: "IceMelt")

        let settingsItem = NSMenuItem(
            title: "IceMelt Settings…",
            action: #selector(AppDelegate.openSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = .command
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let searchItem = NSMenuItem(
            title: "Search Menu Bar Items",
            action: #selector(showSearchPanel),
            keyEquivalent: ""
        )
        if
            let hotkey = hotkey(withAction: .searchMenuBarItems),
            let keyCombination = hotkey.keyCombination
        {
            searchItem.keyEquivalent = keyCombination.key.keyEquivalent
            searchItem.keyEquivalentModifierMask = keyCombination.modifiers.nsEventFlags
        }
        searchItem.target = self
        menu.addItem(searchItem)

        menu.addItem(.separator())

        // Add items to toggle the hidden and always-hidden sections.
        for name: MenuBarSection.Name in [.hidden, .alwaysHidden] {
            guard
                let section = appState.menuBarManager.section(withName: name),
                section.isEnabled
            else {
                continue
            }
            let item = NSMenuItem(
                title: "\(section.isHidden ? "Show" : "Hide") \(name.displayString) Section",
                action: #selector(toggleMenuBarSection),
                keyEquivalent: ""
            )
            if
                let hotkey = section.hotkey,
                let keyCombination = hotkey.keyCombination
            {
                item.keyEquivalent = keyCombination.key.keyEquivalent
                item.keyEquivalentModifierMask = keyCombination.modifiers.nsEventFlags
            }
            item.target = self
            item.representedObject = section
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let checkForUpdatesItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        checkForUpdatesItem.target = self
        menu.addItem(checkForUpdatesItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit IceMelt",
            action: #selector(NSApp.terminate),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = .command
        menu.addItem(quitItem)

        return menu
    }

    /// Shows the control item's menu.
    private func showMenu() {
        guard let appState else {
            return
        }
        let menu = createMenu(with: appState)
        statusItem.showMenu(menu)
    }

    /// Toggles the menu bar section associated with the given menu item.
    @objc private func toggleMenuBarSection(for menuItem: NSMenuItem) {
        guard let section = menuItem.representedObject as? MenuBarSection else {
            return
        }
        section.toggle()
    }

    /// Opens the menu bar search panel.
    @objc private func showSearchPanel() {
        appState?.menuBarManager.searchPanel.show()
    }

    /// Opens the settings window and checks for app updates.
    @objc private func checkForUpdates() {
        guard let appState else {
            return
        }
        appState.updatesManager.checkForUpdates()
    }
}

// MARK: - ControlItemDefaults

/// Proxy getters and setters for a control item's stored
/// UserDefaults values.
enum ControlItemDefaults {
    /// Accesses the value associated with the specified key
    /// and autosave name.
    static subscript<Value>(key: Key<Value>, autosaveName: String) -> Value? {
        get {
            let stringKey = key.stringKey(for: autosaveName)
            return UserDefaults.standard.object(forKey: stringKey) as? Value
        }
        set {
            let stringKey = key.stringKey(for: autosaveName)
            return UserDefaults.standard.set(newValue, forKey: stringKey)
        }
    }

    /// Migrates the given control item defaults key from an old
    /// autosave name to a new autosave name.
    static func migrate<Value>(key: Key<Value>, from oldAutosaveName: String, to newAutosaveName: String) {
        guard newAutosaveName != oldAutosaveName else {
            return
        }
        Self[key, newAutosaveName] = Self[key, oldAutosaveName]
        Self[key, oldAutosaveName] = nil
    }

    /// Performs some initial required setup work before the
    /// creation of a control item.
    fileprivate static func preflightSetup(for controlItem: ControlItem) {
        let autosaveName = controlItem.identifier.rawValue

        // Visible and hidden control items should be added before
        // existing items in the status bar.
        if ControlItemDefaults[.preferredPosition, autosaveName] == nil {
            switch controlItem.identifier {
            case .visible:
                ControlItemDefaults[.preferredPosition, autosaveName] = 0
            case .hidden:
                ControlItemDefaults[.preferredPosition, autosaveName] = 1
            case .alwaysHidden:
                break
            }
        }

        // The control item should be visible by default. We change
        // this after finishing setup, if needed.
        if ControlItemDefaults[.visible, autosaveName] == nil {
            ControlItemDefaults[.visible, autosaveName] = true
        }
        if
            #available(macOS 26.0, *),
            ControlItemDefaults[.visibleCC, autosaveName] == nil
        {
            ControlItemDefaults[.visibleCC, autosaveName] = true
        }
    }
}

// MARK: - ControlItemDefaults.Key

extension ControlItemDefaults {
    /// Keys used to look up UserDefaults values for control items.
    struct Key<Value> {
        /// The raw value of the key.
        let rawValue: String

        /// Returns the full string key for the given autosave name.
        func stringKey(for autosaveName: String) -> String {
            "NSStatusItem \(rawValue) \(autosaveName)"
        }
    }
}

// MARK: ControlItemDefaults.Key<CGFloat>
extension ControlItemDefaults.Key<CGFloat> {
    /// String key: "NSStatusItem Preferred Position autosaveName"
    static let preferredPosition = Self(rawValue: "Preferred Position")
}

// MARK: ControlItemDefaults.Key<Bool>
extension ControlItemDefaults.Key<Bool> {
    /// String key: "NSStatusItem Visible autosaveName"
    static let visible = Self(rawValue: "Visible")

    /// String key: "NSStatusItem VisibleCC autosaveName"
    static let visibleCC = Self(rawValue: "VisibleCC")
}
