//
//  ControlItem.swift
//  IceMelt
//

import Cocoa
import Combine
import OSLog

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

    /// The spacers currently in the menu bar, across all dividers, keyed by
    /// their tags (macOS 27). See ``hostedSpacerFrames``.
    private static var liveSpacers = [MenuBarItemTag: NSStatusItem]()

    /// The frames of the spacers currently in the menu bar, in screen
    /// coordinates, keyed by their tags (macOS 27).
    ///
    /// Read like ``hostedFrames``, so the item manager can tell where the
    /// spacers landed relative to the sections (see
    /// `MenuBarItemManager.hostedSpacerPlacements`).
    static var hostedSpacerFrames: [MenuBarItemTag: CGRect] {
        liveSpacers.reduce(into: [:]) { result, entry in
            guard
                let window = entry.value.button?.window,
                let frame = screenFrame(for: window.frame)
            else {
                return
            }
            result[entry.key] = frame
        }
    }

    /// Converts a status window frame from AppKit's flipped coordinates to
    /// screen coordinates.
    private static func screenFrame(for frame: CGRect) -> CGRect? {
        guard let primaryScreen = NSScreen.screens.first else {
            return nil
        }
        return CGRect(
            x: frame.minX,
            y: primaryScreen.frame.height - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

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
        /// itself included. Each item is kept under the cap of the narrowest
        /// display, so a wide display beside a laptop needs several; eight
        /// covers the widest display Apple sells beside a 13" laptop. The
        /// bound keeps a bad measurement from filling the menu bar with blank
        /// items.
        static let maxHidingItems = 8

        /// The most times a spacer is re-created in search of its place beside
        /// the divider before the search is given up until the next hide.
        static let maxSpacerPlacementAttempts = 8
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

    /// Logger for control items.
    private static let logger = Logger(category: "ControlItem")

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

    /// A blank status item that fills room the divider can't cover on its
    /// own, on macOS 27, with the state of the search for its place beside
    /// the divider. See ``hostedHidingLengths`` and ``updateSpacers(lengths:)``.
    private struct Spacer {
        let statusItem: NSStatusItem
        let tag: MenuBarItemTag

        /// The preferred position the spacer was created with.
        var position: CGFloat

        /// The largest position known to land the spacer too far toward the
        /// trailing end, and the smallest known to land it too far toward
        /// the leading end. Positions grow toward the leading end.
        var tooTrailing: CGFloat = 0
        var tooLeading: CGFloat?

        /// How many times the spacer has been re-created in search of its
        /// place.
        var attempts = 0

        /// Whether the item manager has confirmed the spacer's place.
        var isPlaced = false

        /// When the spacer was created. A verdict that arrives sooner than
        /// the spacer's status window can catch up with the agent's layout
        /// describes the previous attempt, and is ignored.
        let createdAt = ContinuousClock.now
    }

    /// Blank status items that fill the room the divider can't cover on its
    /// own, on macOS 27. See ``hostedHidingLengths``.
    private var spacers = [Spacer]()

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
    ///
    /// A status item has one length on every display, so the cap is that of
    /// the narrowest display: an item over a display's cap is discarded there
    /// yet still consumes room, wiping out the application menu, whereas an
    /// item under the cap that doesn't fit simply overflows, taking the
    /// section with it. Filling the widest display's room therefore hides the
    /// section on every display at once.
    ///
    /// Until a measurement exists the divider stays collapsed, so the
    /// section shows for a moment at launch. Taking the most it can instead
    /// overflows the divider itself, and then which items the agent happens
    /// to pack off the bar decides the first cache's sections, and with them
    /// every later measurement (a visible item counted as hidden stays
    /// hidden). Collapsed, the divider's place among the items is on the
    /// bar for the first cache to read.
    private var hostedHidingLengths: [CGFloat] {
        let padding = Lengths.hostedPadding
        let screenWidth = NSScreen.screens.map(\.frame.width).min() ?? 1_000
        let cap = (screenWidth / 2).rounded(.down) - padding
        guard let width = hostedHidingWidth else {
            return [0]
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

            appState.itemManager.$hostedSpacerPlacements
                .receive(on: DispatchQueue.main)
                .sink { [weak self] placements in
                    self?.reconcileSpacers(placements: placements)
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
        guard isAddedToMenuBar else {
            Self.hostedFrames[identifier] = nil
            return
        }
        Self.hostedFrames[identifier] = Self.screenFrame(for: frame)
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

    /// Matches the divider's spacer items to the given lengths, creating and
    /// removing them as needed.
    ///
    /// The spacers are blank and have no action. They are removed rather
    /// than collapsed when the section is shown: a zero-length item still
    /// occupies the agent's padding, which would leave a gap.
    ///
    /// A spacer fills room only if it sits between the section it hides and
    /// the items that stay visible: the system overflows a contiguous run of
    /// leading items, so a spacer left of a hidden item overflows itself and
    /// leaves that item on the bar. Where a new item lands is set by its
    /// preferred position, which macOS 27 honors for new items only and
    /// measures in an ordering of its own that can't be read, so each spacer
    /// is created at its best-known position and the item manager reports
    /// where it landed (see ``reconcileSpacers(placements:)``).
    @available(macOS 27.0, *)
    private func updateSpacers(lengths: [CGFloat]) {
        while spacers.count > lengths.count {
            removeSpacer(spacers.removeLast())
        }
        var added = false
        while spacers.count < lengths.count {
            let tag = MenuBarItemTag(hostedSpacerFor: identifier, index: spacers.count)
            // The best guess is a position a spacer has already been confirmed
            // at, then one confirmed in an earlier session, then the divider's
            // own recorded position.
            let position = spacers.first { $0.isPlaced }?.position
                ?? ControlItemDefaults[.hostedSpacerPosition, tag.title]
                ?? ControlItemDefaults[.preferredPosition, identifier.rawValue]
                ?? 1
            spacers.append(createSpacer(tag: tag, position: position))
            added = true
        }
        for (index, length) in lengths.enumerated() where spacers[index].statusItem.length != length {
            spacers[index].statusItem.length = length
        }
        if added {
            recacheSoon()
        }
    }

    /// Creates a spacer with the given tag at the given preferred position.
    @available(macOS 27.0, *)
    private func createSpacer(tag: MenuBarItemTag, position: CGFloat) -> Spacer {
        ControlItemDefaults[.preferredPosition, tag.title] = position
        let statusItem = NSStatusBar.system.statusItem(withLength: 0)
        statusItem.autosaveName = tag.title
        // An item whose button is never touched gets a zero-width slot.
        statusItem.button?.title = ""
        statusItem.button?.appearsDisabled = true
        Self.liveSpacers[tag] = statusItem
        return Spacer(statusItem: statusItem, tag: tag, position: position)
    }

    /// Removes the given spacer from the menu bar.
    @available(macOS 27.0, *)
    private func removeSpacer(_ spacer: Spacer) {
        Self.liveSpacers[spacer.tag] = nil
        NSStatusBar.system.removeStatusItem(spacer.statusItem)
        // Removing a status item deletes its preferred position, which is
        // wanted here: the next spacer starts from a confirmed position.
        ControlItemDefaults[.preferredPosition, spacer.tag.title] = nil
    }

    /// Moves any spacer the item manager found out of place, by re-creating
    /// it at a new preferred position.
    ///
    /// Positions grow toward the leading end. A spacer that landed left of
    /// an item it should hide needs a smaller position; one that landed
    /// right of an item that stays visible needs a larger one. Each verdict
    /// narrows the range, and the next attempt bisects it, until the spacer
    /// lands between the two or the attempts run out. A confirmed position
    /// is recorded for the next time the spacer is created.
    @available(macOS 27.0, *)
    private func reconcileSpacers(placements: [MenuBarItemTag: MenuBarItemManager.HostedSpacerPlacement]) {
        var changed = false
        for index in spacers.indices {
            guard let placement = placements[spacers[index].tag] else {
                continue
            }
            var spacer = spacers[index]
            guard spacer.createdAt.duration(to: .now) > .milliseconds(800) else {
                continue
            }
            switch placement {
            case .fits:
                if !spacer.isPlaced {
                    spacer.isPlaced = true
                    ControlItemDefaults[.hostedSpacerPosition, spacer.tag.title] = spacer.position
                    spacers[index] = spacer
                }
                continue
            case .tooFarLeading:
                spacer.tooLeading = min(spacer.tooLeading ?? .infinity, spacer.position)
            case .tooFarTrailing:
                spacer.tooTrailing = max(spacer.tooTrailing, spacer.position)
            }
            guard spacer.attempts < Lengths.maxSpacerPlacementAttempts else {
                continue
            }
            let next: CGFloat
            if let tooLeading = spacer.tooLeading {
                next = (spacer.tooTrailing + tooLeading) / 2
            } else {
                next = max(spacer.position * 2, spacer.position + 100)
            }
            guard abs(next - spacer.position) >= 0.5 else {
                continue // The range has closed without a hit; give up.
            }
            Self.logger.info(
                """
                Spacer \(spacer.tag.title, privacy: .public) landed \(String(describing: placement), privacy: .public) \
                at position \(spacer.position, privacy: .public); trying \(next, privacy: .public)
                """
            )
            removeSpacer(spacer)
            var replacement = createSpacer(tag: spacer.tag, position: next)
            replacement.tooTrailing = spacer.tooTrailing
            replacement.tooLeading = spacer.tooLeading
            replacement.attempts = spacer.attempts + 1
            replacement.statusItem.length = spacer.statusItem.length
            spacers[index] = replacement
            changed = true
        }
        if changed {
            recacheSoon()
        }
    }

    /// Asks the item manager to read the menu bar again shortly, so a
    /// spacer that has just been created gets its placement verdict without
    /// waiting for the next scheduled read.
    @available(macOS 27.0, *)
    private func recacheSoon() {
        guard let appState else {
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(1))
            await appState.itemManager.cacheItemsRegardless()
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

    /// String key: "NSStatusItem Hosted Spacer Position autosaveName"
    ///
    /// The preferred position a spacer was last confirmed in place at
    /// (macOS 27). Unlike the preferred position, it survives the spacer's
    /// removal.
    static let hostedSpacerPosition = Self(rawValue: "Hosted Spacer Position")
}

// MARK: ControlItemDefaults.Key<Bool>
extension ControlItemDefaults.Key<Bool> {
    /// String key: "NSStatusItem Visible autosaveName"
    static let visible = Self(rawValue: "Visible")

    /// String key: "NSStatusItem VisibleCC autosaveName"
    static let visibleCC = Self(rawValue: "VisibleCC")
}
