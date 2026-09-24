//
//  MenuBarItem.swift
//  IceMelt
//

import Cocoa

/// A structural representation of a menu bar item.
struct MenuBarItem: CustomStringConvertible {
    /// The tag associated with this item.
    let tag: MenuBarItemTag

    /// The item's window identifier.
    let windowID: CGWindowID

    /// The identifier of the process that owns the item.
    let ownerPID: pid_t

    /// The identifier of the process that created the item.
    let sourcePID: pid_t?

    /// The item's bounds, specified in screen coordinates.
    let bounds: CGRect

    /// The item's window title.
    let title: String?

    /// A Boolean value that indicates whether the item is on screen.
    let isOnScreen: Bool

    /// A Boolean value that indicates whether the item has a slot of its
    /// own that can be clicked or dragged (macOS 27).
    ///
    /// An item on the bar has one. So does an item laid out at the leading
    /// end while the system overflow is expanded, although it is not on
    /// the bar proper (``isOnScreen`` is `false`). An item stacked in the
    /// collapsed overflow has none. Always equals ``isOnScreen`` before
    /// macOS 27.
    let hasSlot: Bool

    /// A Boolean value that indicates whether this item can be moved.
    var isMovable: Bool {
        tag.isMovable
    }

    /// A Boolean value that indicates whether this item can be hidden.
    var canBeHidden: Bool {
        tag.canBeHidden
    }

    /// A Boolean value that indicates whether this item is one of IceMelt's
    /// control items.
    var isControlItem: Bool {
        tag.isControlItem
    }

    /// A Boolean value that indicates whether this item is a "BentoBox"
    /// item owned by the Control Center.
    var isBentoBox: Bool {
        tag.isBentoBox
    }

    /// A Boolean value that indicates whether this item is a
    /// system-created clone of an actual item, and therefore invalid
    /// for management.
    var isSystemClone: Bool {
        tag.isSystemClone
    }

    /// The frame of the system overflow's chevron on each display, as of
    /// the most recent read of the agent's tree (macOS 27). Absent when the
    /// display has no overflow. Clicking the chevron expands the overflow,
    /// laying its items out at the leading end of the bar; clicking it again
    /// collapses it.
    @MainActor private(set) static var hostedOverflowChevronFrames = [CGDirectDisplayID: CGRect]()

    /// The bit set in the window identifier of a hosted item.
    ///
    /// Hosted items have no window of their own, so they are given a
    /// synthetic identifier derived from their tag. Real window identifiers
    /// are small numbers, so the flag keeps the two ranges apart.
    static let hostedWindowIDFlag: CGWindowID = 1 << 30

    /// A Boolean value that indicates whether this item is hosted by
    /// `MenuBarAgent` (macOS 27 and later) rather than backed by a window.
    ///
    /// A hosted item's ``bounds`` are its only geometry: the window server
    /// APIs cannot resolve its ``windowID``, and it can't be captured, moved
    /// or clicked through a window.
    var isHosted: Bool {
        windowID & Self.hostedWindowIDFlag != 0
    }

    /// The application that owns the item.
    ///
    /// - Note: In macOS 26 and later, this property always returns the
    ///   Control Center. To get the actual application that created the
    ///   item, use ``sourceApplication``.
    var owningApplication: NSRunningApplication? {
        NSRunningApplication(processIdentifier: ownerPID)
    }

    /// The application that created the item.
    ///
    /// - Note: Prior to macOS 26, this property and ``owningApplication``
    ///   are functionally equivalent.
    var sourceApplication: NSRunningApplication? {
        guard let sourcePID else {
            return nil
        }
        return NSRunningApplication(processIdentifier: sourcePID)
    }

    // TODO: Generate this once, during initialization.
    /// A name associated with the item, suited for display.
    var displayName: String {
        /// Converts "UpperCamelCase" to "Title Case".
        ///
        /// Ignores cases where a single lowercase letter immediately
        /// precedes an uppercase letter (i.e. "WiFi").
        func toTitleCase<S: StringProtocol>(_ s: S) -> String {
            String(s).replacing(/([a-z]{2})([A-Z])/) { $0.output.1 + " " + $0.output.2 }
        }

        guard !isControlItem else {
            return Constants.displayName
        }

        lazy var fallbackName = "Menu Bar Item"

        guard let sourceApplication else {
            return fallbackName
        }

        lazy var sourceName = sourceApplication.localizedName ?? sourceApplication.bundleIdentifier

        guard let title else {
            return sourceName ?? fallbackName
        }

        lazy var bestName = sourceName ?? title

        guard !isBentoBox else {
            if tag == .controlCenter {
                return bestName
            }
            return title
        }

        // Most items use their computed "best name", but we handle
        // a few special cases for system items.
        let displayName = switch tag.namespace {
        case .menuBarAgent:
            // "com.apple.menuextra.controlcenter" -> "Control Center"
            Self.hostedExtraDisplayName(for: title)
        case .passwords, .weather, .textInputMenuAgent:
            // "PasswordsMenuBarExtra" -> "Passwords"
            // "WeatherMenu" -> "Weather"
            // "TextInputMenuAgent" -> "Text Input"
            toTitleCase(bestName.replacing(/Menu.*/, with: ""))
        case .controlCenter:
            if let match = title.prefixMatch(of: /Hearing/) {
                // Changed from "Hearing" to "Hearing_GlowE" in macOS 15.4
                toTitleCase(match.output)
            } else {
                toTitleCase(title)
            }
        case .systemUIServer:
            if let match = title.firstMatch(of: /TimeMachine/) {
                // Sonoma:  "TimeMachine.TMMenuExtraHost"
                // Sequoia: "TimeMachineMenuExtra.TMMenuExtraHost"
                // Tahoe:   "com.apple.menuextra.TimeMachine"
                toTitleCase(match.output)
            } else {
                toTitleCase(title)
            }
        default:
            bestName
        }

        // Provide some extra context if the name is just a UUID.
        if UUID(uuidString: displayName) != nil, let sourceName {
            return "\(sourceName) (\(displayName))"
        }

        return displayName
    }

    /// A textual representation of the item.
    var description: String {
        "\(displayName) (\(tag))"
    }

    /// A string to use for logging purposes.
    var logString: String {
        "<\(tag) (windowID: \(windowID))>"
    }

    /// Returns a display name for a system menu extra hosted by `MenuBarAgent`,
    /// given its accessibility identifier.
    private static func hostedExtraDisplayName(for identifier: String) -> String {
        let key = identifier.replacing(/^com\.apple\.menuextra\./, with: "")
        return switch key {
        case "wifi": "Wi‑Fi"
        case "controlcenter": "Control Center"
        case "focusmode": "Focus"
        case "": identifier
        default: key.prefix(1).uppercased() + key.dropFirst()
        }
    }

    /// Creates a menu bar item for an item hosted by `MenuBarAgent`.
    ///
    /// The window identifier is synthesized from the tag, so the same item
    /// keeps the same identifier from one read of the agent's tree to the next.
    ///
    /// An item in the system overflow is not on screen. The agent still lists
    /// it, but at a stacked position that says nothing about where it sits.
    @available(macOS 27.0, *)
    private init(hosted item: HostedMenuBarItem, tag: MenuBarItemTag, ownerPID: pid_t, isOnScreen: Bool, hasSlot: Bool) {
        self.tag = tag
        self.windowID = Self.hostedWindowIDFlag | (CGWindowID(truncatingIfNeeded: tag.hashValue) & (Self.hostedWindowIDFlag - 1))
        self.ownerPID = ownerPID
        self.sourcePID = item.sourcePID
        self.bounds = item.frame
        self.title = item.identifier
        self.isOnScreen = isOnScreen
        self.hasSlot = hasSlot
    }

    /// Creates a menu bar item without checks.
    ///
    /// This initializer does not perform validity checks on its parameters.
    /// Only call it if you are certain the window is a valid menu bar item.
    private init(uncheckedItemWindow itemWindow: WindowInfo) {
        self.tag = MenuBarItemTag(uncheckedItemWindow: itemWindow)
        self.windowID = itemWindow.windowID
        self.ownerPID = itemWindow.ownerPID
        self.sourcePID = itemWindow.ownerPID
        self.bounds = itemWindow.bounds
        self.title = itemWindow.title
        self.isOnScreen = itemWindow.isOnScreen
        self.hasSlot = itemWindow.isOnScreen
    }

    /// Creates a menu bar item without checks.
    ///
    /// This initializer does not perform validity checks on its parameters.
    /// Only call it if you are certain the window is a valid menu bar item
    /// and the source pid belongs to the application that created it.
    @available(macOS 26.0, *)
    private init(uncheckedItemWindow itemWindow: WindowInfo, sourcePID: pid_t?) {
        self.tag = MenuBarItemTag(uncheckedItemWindow: itemWindow, sourcePID: sourcePID)
        self.windowID = itemWindow.windowID
        self.ownerPID = itemWindow.ownerPID
        self.sourcePID = sourcePID
        self.bounds = itemWindow.bounds
        self.title = itemWindow.title
        self.isOnScreen = itemWindow.isOnScreen
        self.hasSlot = itemWindow.isOnScreen
    }
}

// MARK: - MenuBarItem List

extension MenuBarItem {
    /// Options that specify the menu bar items in a list.
    struct ListOption: OptionSet {
        let rawValue: Int

        /// Specifies menu bar items that are currently on screen.
        static let onScreen = ListOption(rawValue: 1 << 0)

        /// Specifies menu bar items on the currently active space.
        static let activeSpace = ListOption(rawValue: 1 << 1)
    }

    /// Creates and returns a list of menu bar items windows for the given display.
    ///
    /// - Parameters:
    ///   - display: An identifier for a display. Pass `nil` to return the menu bar
    ///     item windows across all available displays.
    ///   - option: Options that filter the returned list. Pass an empty option set
    ///     to return all available menu bar item windows.
    static func getMenuBarItemWindows(on display: CGDirectDisplayID? = nil, option: ListOption) -> [WindowInfo] {
        var bridgingOption: Bridging.MenuBarWindowListOption = .itemsOnly
        var displayBoundsPredicate: (CGWindowID) -> Bool = { _ in true }

        if let display {
            bridgingOption.insert(.onScreen)
            let displayBounds = CGDisplayBounds(display)
            displayBoundsPredicate = { windowID in
                Bridging.windowIntersectsDisplayBounds(windowID, displayBounds)
            }
        } else if option.contains(.onScreen) {
            bridgingOption.insert(.onScreen)
        }
        if option.contains(.activeSpace) {
            bridgingOption.insert(.activeSpace)
        }

        return Bridging.getMenuBarWindowList(option: bridgingOption)
            .reversed().compactMap { windowID in
                guard
                    displayBoundsPredicate(windowID),
                    let window = WindowInfo(windowID: windowID)
                else {
                    return nil
                }
                return window
            }
    }

    /// Creates and returns a list of menu bar items using experimental
    /// source pid retrieval for macOS 26.
    @available(macOS 26.0, *)
    private static func getMenuBarItemsExperimental(on display: CGDirectDisplayID?, option: ListOption) async -> [MenuBarItem] {
        let windows = getMenuBarItemWindows(on: display, option: option)
        let sourcePIDs = await MenuBarItemService.Connection.shared.sourcePIDs(for: windows)
        return windows.map { window in
            MenuBarItem(uncheckedItemWindow: window, sourcePID: sourcePIDs[window.windowID])
        }
    }

    /// Creates and returns the menu bar items hosted by `MenuBarAgent`, for
    /// macOS 27 and later, keyed by the display that hosts them.
    ///
    /// Every display hosts its own copy of every item. IceMelt's own control
    /// items are recognized by matching the hosted frames against the frames
    /// of the control items' status windows, which AppKit keeps in step with
    /// the agent's layout; the blank spacers a divider hides its section with
    /// are recognized the same way, and are included only when asked for,
    /// since nothing but the item manager's measurement should see them.
    /// Items of other processes are identified by their process, and numbered
    /// left to right when a process has more than one, since the agent
    /// exposes no stable title.
    @available(macOS 27.0, *)
    static func getHostedMenuBarItemsByDisplay(includingSpacers: Bool = false) async -> [CGDirectDisplayID: [MenuBarItem]] {
        let hosted = await MenuBarItemService.Connection.shared.hostedItems()
        guard !hosted.isEmpty else {
            return [:]
        }

        var chevronFrames = [CGDirectDisplayID: CGRect]()
        for item in hosted where item.isOverflowChevron {
            for screen in NSScreen.screens where CGDisplayBounds(screen.displayID).intersects(item.hostFrame) {
                chevronFrames[screen.displayID] = item.frame
            }
        }
        await MainActor.run {
            hostedOverflowChevronFrames = chevronFrames
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let agentPID = hosted.first { $0.isSystemExtra }?.sourcePID
            ?? NSRunningApplication
                .runningApplications(withBundleIdentifier: HostedMenuBarItem.agentBundleIdentifier)
                .first?.processIdentifier
            ?? 0
        var ownFrames = await ControlItem.hostedFrames.reduce(into: [MenuBarItemTag: CGRect]()) { result, entry in
            result[entry.key.tag] = entry.value
        }
        if includingSpacers {
            ownFrames.merge(await ControlItem.hostedSpacerFrames) { current, _ in current }
        }

        // Items of other processes are numbered within their namespace, so
        // two processes of one app (an app and its helper) can't collide.
        func namespace(for item: HostedMenuBarItem) -> MenuBarItemTag.Namespace {
            if let app = NSRunningApplication(processIdentifier: item.sourcePID) {
                .optional(app.bundleIdentifier ?? app.localizedName)
            } else {
                .null
            }
        }

        var result = [CGDirectDisplayID: [MenuBarItem]]()
        let displayIDs = NSScreen.screens.map(\.displayID)

        for displayID in displayIDs {
            let displayBounds = CGDisplayBounds(displayID)
            var seen = Set<HostedMenuBarItem>()
            let onDisplay = hosted
                .filter { displayBounds.intersects($0.hostFrame) && !$0.isOverflowChevron }
                // The agent can list an item twice with the same frame while it
                // is in the overflow. Keep the first.
                .filter { seen.insert($0).inserted }
                .sorted { $0.frame.minX < $1.frame.minX }

            // Items in the overflow are listed stacked at one position; items on
            // the bar never share one. An item alone at its stacked position,
            // or laid out at the leading end while the overflow is expanded,
            // is told apart by lying left of the chevron. Our own items are
            // exempt: the divider's slot extends under the chevron.
            var countsByMinX = [Int: Int]()
            for item in onDisplay {
                countsByMinX[Int(item.frame.minX), default: 0] += 1
            }
            let chevronMinX = chevronFrames[displayID]?.minX
            func hasSlot(_ item: HostedMenuBarItem) -> Bool {
                countsByMinX[Int(item.frame.minX)] == 1
            }
            func isOnScreen(_ item: HostedMenuBarItem) -> Bool {
                guard hasSlot(item) else {
                    return false
                }
                if let chevronMinX, item.sourcePID != ownPID {
                    return item.frame.minX >= chevronMinX
                }
                return true
            }

            var slotCounts = [MenuBarItemTag.Namespace: Int]()
            for item in onDisplay where !item.isSystemExtra && item.sourcePID != ownPID {
                slotCounts[namespace(for: item), default: 0] += 1
            }
            var ordinals = [MenuBarItemTag.Namespace: Int]()

            result[displayID] = onDisplay.compactMap { item in
                let tag: MenuBarItemTag
                if item.isSystemExtra {
                    guard let identifier = item.identifier else {
                        return nil
                    }
                    tag = MenuBarItemTag(namespace: .menuBarAgent, title: identifier)
                } else if item.sourcePID == ownPID {
                    // Match the slot to the nearest of our items by position. A
                    // slot of ours that matches none is skipped: a spacer when
                    // spacers weren't asked for, or a status window that has not
                    // caught up with the agent's layout yet.
                    let candidates = ownFrames.filter { _, frame in
                        abs(frame.minX - item.frame.minX) <= 2 && abs(frame.minY - item.frame.minY) <= 40
                    }
                    guard let match = candidates.min(by: { abs($0.value.minX - item.frame.minX) < abs($1.value.minX - item.frame.minX) }) else {
                        return nil
                    }
                    tag = match.key
                } else {
                    let namespace = namespace(for: item)
                    let title: String
                    if slotCounts[namespace, default: 0] > 1 {
                        let ordinal = ordinals[namespace, default: 0]
                        ordinals[namespace] = ordinal + 1
                        title = "Item-\(ordinal)"
                    } else {
                        title = ""
                    }
                    tag = MenuBarItemTag(namespace: namespace, title: title)
                }
                return MenuBarItem(
                    hosted: item,
                    tag: tag,
                    ownerPID: agentPID,
                    isOnScreen: isOnScreen(item),
                    hasSlot: hasSlot(item)
                )
            }
        }

        return result
    }

    /// Creates and returns a list of menu bar items hosted by `MenuBarAgent`,
    /// for macOS 27 and later, on the given display, or on the one with the
    /// active menu bar. See ``getHostedMenuBarItemsByDisplay(includingSpacers:)``.
    @available(macOS 27.0, *)
    private static func getHostedMenuBarItems(on display: CGDirectDisplayID?) async -> [MenuBarItem] {
        let displayID = display ?? Bridging.getActiveMenuBarDisplayID() ?? CGMainDisplayID()
        return await getHostedMenuBarItemsByDisplay()[displayID] ?? []
    }

    /// Creates and returns a list of menu bar items, defaulting to the
    /// legacy source pid behavior, prior to macOS 26.
    private static func getMenuBarItemsLegacyMethod(on display: CGDirectDisplayID?, option: ListOption) -> [MenuBarItem] {
        getMenuBarItemWindows(on: display, option: option).map { window in
            MenuBarItem(uncheckedItemWindow: window)
        }
    }

    /// Creates and returns a list of menu bar items for the given display.
    ///
    /// - Parameters:
    ///   - display: An identifier for a display. Pass `nil` to return the menu bar
    ///     items across all available displays.
    ///   - option: Options that filter the returned list. Pass an empty option set
    ///     to return all available menu bar items.
    static func getMenuBarItems(on display: CGDirectDisplayID? = nil, option: ListOption) async -> [MenuBarItem] {
        if #available(macOS 27.0, *) {
            await getHostedMenuBarItems(on: display)
        } else if #available(macOS 26.0, *) {
            await getMenuBarItemsExperimental(on: display, option: option)
        } else {
            getMenuBarItemsLegacyMethod(on: display, option: option)
        }
    }
}

// MARK: MenuBarItem: Equatable
extension MenuBarItem: Equatable {
    static func == (lhs: MenuBarItem, rhs: MenuBarItem) -> Bool {
        lhs.tag == rhs.tag &&
        lhs.windowID == rhs.windowID &&
        lhs.ownerPID == rhs.ownerPID &&
        lhs.sourcePID == rhs.sourcePID &&
        NSStringFromRect(lhs.bounds) == NSStringFromRect(rhs.bounds) &&
        lhs.title == rhs.title &&
        lhs.isOnScreen == rhs.isOnScreen &&
        lhs.hasSlot == rhs.hasSlot
    }
}

// MARK: MenuBarItem: Hashable
extension MenuBarItem: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(tag)
        hasher.combine(windowID)
        hasher.combine(ownerPID)
        hasher.combine(sourcePID)
        hasher.combine(NSStringFromRect(bounds))
        hasher.combine(title)
        hasher.combine(isOnScreen)
        hasher.combine(hasSlot)
    }
}

// MARK: - MenuBarItemTag Helper

private extension MenuBarItemTag {
    /// Creates a tag without checks.
    ///
    /// This initializer does not perform validity checks on its parameters.
    /// Only call it if you are certain the window is a valid menu bar item.
    init(uncheckedItemWindow itemWindow: WindowInfo) {
        self.namespace = Namespace(uncheckedItemWindow: itemWindow)
        self.title = itemWindow.title ?? ""
    }

    /// Creates a tag without checks.
    ///
    /// This initializer does not perform validity checks on its parameters.
    /// Only call it if you are certain the window is a valid menu bar item
    /// and the source pid belongs to the application that created it.
    @available(macOS 26.0, *)
    init(uncheckedItemWindow itemWindow: WindowInfo, sourcePID: pid_t?) {
        self.namespace = Namespace(uncheckedItemWindow: itemWindow, sourcePID: sourcePID)
        self.title = itemWindow.title ?? ""
    }
}

// MARK: - MenuBarItemTag.Namespace Helper

private extension MenuBarItemTag.Namespace {
    private static var uuidCache = [CGWindowID: UUID]()

    /// Creates a namespace without checks.
    ///
    /// This initializer does not perform validity checks on its parameters.
    /// Only call it if you are certain the window is a valid menu bar item.
    init(uncheckedItemWindow itemWindow: WindowInfo) {
        // Most apps have a bundle ID, but we should be able to handle apps
        // that don't. We should also be able to handle daemons and helpers,
        // which are more likely not to have a bundle ID.
        //
        // Use the name of the owning process as a fallback. The non-localized
        // name seems less likely to change, so let's prefer it as a (somewhat)
        // stable identifier.
        if let app = itemWindow.owningApplication {
            self = .optional(app.bundleIdentifier ?? itemWindow.ownerName ?? app.localizedName)
        } else {
            self = .optional(itemWindow.ownerName)
        }
    }

    /// Creates a namespace without checks.
    ///
    /// This initializer does not perform validity checks on its parameters.
    /// Only call it if you are certain the window is a valid menu bar item
    /// and the source pid belongs to the application that created it.
    @available(macOS 26.0, *)
    init(uncheckedItemWindow itemWindow: WindowInfo, sourcePID: pid_t?) {
        // Most apps have a bundle ID, but we should be able to handle apps
        // that don't. We should also be able to handle daemons and helpers,
        // which are more likely not to have a bundle ID.
        if let sourcePID, let app = NSRunningApplication(processIdentifier: sourcePID) {
            self = .optional(app.bundleIdentifier ?? app.localizedName)
        } else if let uuid = Self.uuidCache[itemWindow.windowID] {
            self = .uuid(uuid)
        } else {
            let uuid = UUID()
            Self.uuidCache[itemWindow.windowID] = uuid
            self = .uuid(uuid)
        }
    }
}
