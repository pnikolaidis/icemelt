//
//  MenuBarSection.swift
//  IceMelt
//

import OSLog
import SwiftUI

/// A representation of a section in a menu bar.
@MainActor
final class MenuBarSection {
    /// The name of a menu bar section.
    enum Name: CaseIterable {
        case visible
        case hidden
        case alwaysHidden

        /// A string to show in the interface.
        var displayString: String {
            switch self {
            case .visible: "Visible"
            case .hidden: "Hidden"
            case .alwaysHidden: "Always-Hidden"
            }
        }

        /// A string to use for logging purposes.
        var logString: String {
            switch self {
            case .visible: "visible section"
            case .hidden: "hidden section"
            case .alwaysHidden: "always-hidden section"
            }
        }

        /// Localized string key representation.
        var localized: LocalizedStringKey {
            LocalizedStringKey(displayString)
        }
    }

    /// The name of the section.
    let name: Name

    /// The control item that manages the section.
    let controlItem: ControlItem

    /// The shared app state.
    private weak var appState: AppState?

    /// A timer that manages rehiding the section.
    private var rehideTimer: Timer?

    /// When ``toggle(caller:line:)`` last changed the section's state.
    private var lastToggle: ContinuousClock.Instant?

    /// An event monitor that handles starting the rehide timer when the mouse
    /// is outside of the menu bar.
    private var rehideMonitor: EventMonitor?

    /// A Boolean value that indicates whether the IceMelt Bar should be used.
    ///
    /// Not while sections are hidden through the allowlist (macOS 27): the
    /// apps it hides aren't drawn, so the bar can't picture them.
    private var useIceMeltBar: Bool {
        if #available(macOS 27.0, *), MenuBarAllowlist.isAvailable {
            return false
        }
        return appState?.settings.general.useIceMeltBar ?? false
    }

    /// A weak reference to the menu bar manager.
    private weak var menuBarManager: MenuBarManager? {
        appState?.menuBarManager
    }

    /// The best screen to show the IceMelt Bar on.
    private weak var screenForIceMeltBar: NSScreen? {
        guard let appState else {
            return nil
        }
        if appState.activeSpace.isFullscreen {
            return NSScreen.screenWithMouse ?? NSScreen.main
        } else {
            return NSScreen.main
        }
    }

    /// A Boolean value that indicates whether the section is hidden.
    var isHidden: Bool {
        if useIceMeltBar {
            if controlItem.state == .showSection {
                return false
            }
            switch name {
            case .visible, .hidden:
                return menuBarManager?.iceMeltBarPanel.currentSection != .hidden
            case .alwaysHidden:
                return menuBarManager?.iceMeltBarPanel.currentSection != .alwaysHidden
            }
        }
        switch name {
        case .visible, .hidden:
            if menuBarManager?.iceMeltBarPanel.currentSection == .hidden {
                return false
            }
            return controlItem.state == .hideSection
        case .alwaysHidden:
            if menuBarManager?.iceMeltBarPanel.currentSection == .alwaysHidden {
                return false
            }
            return controlItem.state == .hideSection
        }
    }

    /// A Boolean value that indicates whether the section is enabled.
    var isEnabled: Bool {
        if case .visible = name {
            // The visible section should always be enabled.
            return true
        }
        return controlItem.isAddedToMenuBar
    }

    /// The hotkey to toggle the section.
    var hotkey: Hotkey? {
        guard let hotkeys = appState?.settings.hotkeys else {
            return nil
        }
        return switch name {
        case .visible: nil
        case .hidden: hotkeys.hotkey(withAction: .toggleHiddenSection)
        case .alwaysHidden: hotkeys.hotkey(withAction: .toggleAlwaysHiddenSection)
        }
    }

    /// Creates a section with the given name and control item.
    init(name: Name, controlItem: ControlItem) {
        self.name = name
        self.controlItem = controlItem
    }

    /// Creates a section with the given name.
    convenience init(name: Name) {
        let controlItem = switch name {
        case .visible:
            ControlItem(identifier: .visible)
        case .hidden:
            ControlItem(identifier: .hidden)
        case .alwaysHidden:
            ControlItem(identifier: .alwaysHidden)
        }
        self.init(name: name, controlItem: controlItem)
    }

    /// Performs the initial setup of the section.
    func performSetup(with appState: AppState) {
        self.appState = appState
        controlItem.performSetup(with: appState)
    }

    /// Shows the section.
    func show(caller: String = #fileID, line: Int = #line) {
        guard let menuBarManager, isHidden else {
            return
        }
        Logger.default.notice("Showing \(self.name.logString, privacy: .public) section (from \(caller, privacy: .public):\(line, privacy: .public))")

        guard controlItem.isAddedToMenuBar else {
            // The section is disabled.
            // TODO: Can we use isEnabled for this check?
            return
        }

        if useIceMeltBar {
            // Make sure hidden and always-hidden control items are collapsed.
            // Still update the visible control item (IceMelt icon) state to show
            // its alternate icon.
            for section in menuBarManager.sections {
                switch section.name {
                case .visible:
                    section.controlItem.state = .showSection
                case .hidden, .alwaysHidden:
                    section.controlItem.state = .hideSection
                }
            }

            if let screen = screenForIceMeltBar {
                Task {
                    switch name {
                    case .visible, .hidden:
                        await menuBarManager.iceMeltBarPanel.show(section: .hidden, on: screen)
                    case .alwaysHidden:
                        await menuBarManager.iceMeltBarPanel.show(section: .alwaysHidden, on: screen)
                    }
                    startRehideChecks()
                }
            }

            return // We're done.
        }

        // If we made it here, we're not using the IceMelt Bar.
        // Make sure it's closed.
        menuBarManager.iceMeltBarPanel.close()
        appState?.itemManager.beginSectionTransition(opening: true)

        switch name {
        case .visible, .hidden:
            for section in menuBarManager.sections where section.name != .alwaysHidden {
                section.controlItem.state = .showSection
            }
        case .alwaysHidden:
            for section in menuBarManager.sections {
                section.controlItem.state = .showSection
            }
        }

        if #available(macOS 27.0, *) {
            appState?.itemManager.updateMenuBarAllowlist()
        }
        startRehideChecks()
        recacheAfterStateChange()
        setOverflowExpandedAfterReflow(true)
    }

    /// Opens or closes the system overflow once the bar has reflowed after
    /// the section changes state (macOS 27), so a section shown in place
    /// shows the items that don't fit beside the chevron too, left of the
    /// notch, and they go away with it. A click on the chevron itself has
    /// already done this, and then there is nothing to do.
    private func setOverflowExpandedAfterReflow(_ expanded: Bool) {
        guard #available(macOS 27.0, *), let appState, !useIceMeltBar, name != .alwaysHidden else {
            return
        }
        Task {
            // Closing is checked again while the bar settles: read too early,
            // an overflow still opening looks closed, and stays open with the
            // hidden items laid out over the application menu.
            let delays: [Duration] = expanded ? [.milliseconds(500)] : [.milliseconds(500), .milliseconds(700), .milliseconds(1_000)]
            for delay in delays {
                try? await Task.sleep(for: delay)
                // The section may have changed state again meanwhile.
                guard isHidden != expanded else {
                    return
                }
                await appState.itemManager.setHostedOverflowExpanded(expanded)
            }
            // Places the cover over the open overflow's » (see
            // `OverflowChevronMask`) once the overflow has opened.
            if expanded {
                try? await Task.sleep(for: .milliseconds(300))
                await appState.itemManager.cacheItemsRegardless()
            }
        }
    }

    /// Hides the section.
    func hide(caller: String = #fileID, line: Int = #line) {
        guard let menuBarManager, !isHidden else {
            return
        }
        Logger.default.notice("Hiding \(self.name.logString, privacy: .public) section (from \(caller, privacy: .public):\(line, privacy: .public))")

        menuBarManager.iceMeltBarPanel.close() // Make sure IceMelt Bar is always closed.
        menuBarManager.showOnHoverAllowed = true
        if !useIceMeltBar {
            appState?.itemManager.beginSectionTransition(opening: false)
            if #available(macOS 27.0, *), name != .alwaysHidden {
                appState?.itemManager.closeHostedOverflowAhead()
            }
        }

        switch name {
        case _ where useIceMeltBar, .visible, .hidden:
            for section in menuBarManager.sections {
                section.controlItem.state = .hideSection
            }
        case .alwaysHidden:
            controlItem.state = .hideSection
        }

        if #available(macOS 27.0, *) {
            appState?.itemManager.updateMenuBarAllowlist()
        }
        stopRehideChecks()
        if !useIceMeltBar {
            appState?.itemManager.restoreOverflowChevronCover()
        }
        recacheAfterStateChange()
        setOverflowExpandedAfterReflow(false)
    }

    /// Toggles the visibility of the section.
    ///
    /// A toggle within 300ms of the last one is ignored. One click on the
    /// menu bar can reach both the divider and the show-on-click handler
    /// (macOS 27): the divider's frame is read only as the items are
    /// cached, so while the bar reflows a click on it can read as one on
    /// empty space, and the two toggles undo each other.
    func toggle(caller: String = #fileID, line: Int = #line) {
        let now = ContinuousClock.now
        if let lastToggle, lastToggle.duration(to: now) < .milliseconds(300) {
            Logger.default.debug("Ignoring a second toggle of \(self.name.logString, privacy: .public) section (from \(caller, privacy: .public):\(line, privacy: .public))")
            return
        }
        lastToggle = now
        if isHidden { show(caller: caller, line: line) } else { hide(caller: caller, line: line) }
    }

    /// Re-measures the menu bar shortly after a section changes state.
    ///
    /// On macOS 27 the hiding widths of the dividers depend on what is on
    /// the bar (see `MenuBarItemManager.hostedHidingWidths`), and a section
    /// showing or hiding changes that.
    private func recacheAfterStateChange() {
        guard #available(macOS 27.0, *), let appState else {
            return
        }
        // Read a few times while the bar settles, so the cover over the
        // system's « (see `OverflowChevronMask`) follows it within moments
        // rather than at the next scheduled read.
        Task {
            for delay: Duration in [.milliseconds(300), .milliseconds(400), .milliseconds(500), .milliseconds(800)] {
                try? await Task.sleep(for: delay)
                await appState.itemManager.cacheItemsRegardless()
            }
        }
    }

    /// Starts running checks to determine when to rehide the section.
    private func startRehideChecks() {
        rehideTimer?.invalidate()
        rehideMonitor?.stop()

        guard
            let appState,
            appState.settings.general.autoRehide,
            case .timed = appState.settings.general.rehideStrategy
        else {
            return
        }

        rehideMonitor = EventMonitor.universal(for: .mouseMoved) { [weak self] event in
            guard
                let self,
                let screen = NSScreen.main
            else {
                return event
            }
            if NSEvent.mouseLocation.y < screen.visibleFrame.maxY {
                if rehideTimer == nil {
                    rehideTimer = .scheduledTimer(
                        withTimeInterval: appState.settings.general.rehideInterval,
                        repeats: false
                    ) { [weak self] _ in
                        guard
                            let self,
                            let screen = NSScreen.main
                        else {
                            return
                        }
                        if NSEvent.mouseLocation.y < screen.visibleFrame.maxY {
                            Task {
                                await self.hide()
                            }
                        } else {
                            Task {
                                await self.startRehideChecks()
                            }
                        }
                    }
                }
            } else {
                rehideTimer?.invalidate()
                rehideTimer = nil
            }
            return event
        }

        rehideMonitor?.start()
    }

    /// Stops running checks to determine when to rehide the section.
    private func stopRehideChecks() {
        rehideTimer?.invalidate()
        rehideMonitor?.stop()
        rehideTimer = nil
        rehideMonitor = nil
    }
}
