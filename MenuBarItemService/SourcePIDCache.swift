//
//  SourcePIDCache.swift
//  MenuBarItemService
//

import AXSwift
import Cocoa
import Combine
import os

/// A cache for the source process identifiers for menu bar item windows.
///
/// We use the term "source process" to refer to the process that created
/// a menu bar item. Originally, we used the CGWindowList API to get the
/// window's owning process (`kCGWindowOwnerPID`), which was always the
/// source process. However, as of macOS 26, item windows are owned by
/// the Control Center.
///
/// We can find what we need using the Accessibility API, but doing it
/// efficiently ends up being a fairly complex process. Since calls to
/// Accessibility are thread blocking, we do most of the heavy lifting
/// in a dedicated XPC service, which we then call asynchronously from
/// the main app.
final class SourcePIDCache {
    /// An object that contains a running application and provides an
    /// interface to access relevant information, such as its process
    /// identifier and extras menu bar.
    private final class CachedApplication {
        private let runningApp: NSRunningApplication
        private var extrasMenuBar: UIElement?

        /// The app's process identifier.
        var processIdentifier: pid_t {
            runningApp.processIdentifier
        }

        /// A Boolean value indicating whether the app's extras menu
        /// bar has been successfully created and stored.
        var hasExtrasMenuBar: Bool {
            extrasMenuBar != nil
        }

        /// A Boolean value indicating whether the app has a prohibited
        /// activation policy.
        ///
        /// Prohibited apps that are packaged as an `.app` bundle (such as
        /// `LSBackgroundOnly` apps) can still own menu bar items, so they
        /// must not be skipped. Prohibited processes that are not `.app`
        /// packaged (XPC services, app extensions, daemons) cannot.
        private var isProhibited: Bool {
            runningApp.activationPolicy == .prohibited
        }

        /// A Boolean value indicating whether the app is in a valid
        /// state for making accessibility calls.
        var isValidForAccessibility: Bool {
            // These checks help prevent blocking that can occur when
            // calling AX APIs while the app is an invalid state.
            runningApp.isFinishedLaunching &&
            !runningApp.isTerminated &&
            (!isProhibited || runningApp.bundleURL?.pathExtension == "app") &&
            !Bridging.isProcessUnresponsive(processIdentifier)
        }

        /// Creates a `CachedApplication` instance with the given running
        /// application.
        init(_ runningApp: NSRunningApplication) {
            self.runningApp = runningApp
        }

        /// Returns the accessibility element representing the app's extras
        /// menu bar, creating it if necessary.
        ///
        /// When the element is first created, it gets stored for efficient
        /// access on subsequent calls.
        func getOrCreateExtrasMenuBar() -> UIElement? {
            if let extrasMenuBar {
                return extrasMenuBar
            }
            guard
                isValidForAccessibility,
                let app = AXHelpers.application(for: runningApp)
            else {
                return nil
            }
            if isProhibited {
                // Prohibited apps often have no accessibility server, in
                // which case calls time out instead of returning an error.
                // Shorten the timeout so they can't stall resolution.
                AXHelpers.setMessagingTimeout(0.25, for: app)
            }
            guard let bar = AXHelpers.extrasMenuBar(for: app) else {
                return nil
            }
            extrasMenuBar = bar
            return bar
        }
    }

    /// An item element in some app's extras menu bar, paired with the app's
    /// process identifier and the element's live-read frame.
    private struct ExtrasMenuBarItem {
        let pid: pid_t
        let element: UIElement
        let frame: CGRect
    }

    /// State for the cache.
    private struct State {
        var apps = [CachedApplication]()
        var pids = [CGWindowID: pid_t]()

        /// Reorders the cached apps so that those that are confirmed
        /// to have an extras menu bar are first in the array.
        private mutating func partitionApps() {
            var lhs = [CachedApplication]()
            var rhs = [CachedApplication]()

            for app in apps {
                if app.hasExtrasMenuBar {
                    lhs.append(app)
                } else {
                    rhs.append(app)
                }
            }

            apps = lhs + rhs
        }

        /// Collects the item elements of every cached app's extras menu bar,
        /// with each element's frame read live from the accessibility server.
        private mutating func collectExtrasMenuBarItems() -> [ExtrasMenuBarItem] {
            partitionApps()

            var items = [ExtrasMenuBarItem]()
            for app in apps {
                guard let bar = app.getOrCreateExtrasMenuBar() else {
                    continue
                }
                for child in AXHelpers.children(for: bar) {
                    guard
                        AXHelpers.isEnabled(child),
                        let frame = AXHelpers.frame(for: child)
                    else {
                        continue
                    }
                    items.append(ExtrasMenuBarItem(pid: app.processIdentifier, element: child, frame: frame))
                }
            }
            return items
        }

        /// Updates the cached process identifiers for the given windows.
        ///
        /// Attribution works in two phases. First, each accessibility item is
        /// asked for its backing window directly (`_AXUIElementGetWindow`) —
        /// exact when it works, but the system returns failure for most menu
        /// bar items as of macOS 26. The remainder are matched geometrically:
        /// every (item, window) pair where the window's horizontal span
        /// contains the item's midpoint is scored by center distance (with
        /// width difference as a tiebreaker), and pairs are claimed greedily,
        /// best score first, so each item and each window is assigned at most
        /// once. Matching is horizontal only — accessibility frames are
        /// vertically centered in the bar while item windows span its full
        /// height, so comparing vertical geometry would only add noise.
        mutating func updatePIDs(for windows: [WindowInfo]) {
            guard AXHelpers.isProcessTrusted() else {
                return
            }

            // Re-read window bounds so we match against current positions.
            // A window that no longer exists is dropped.
            let unresolved: [(windowID: CGWindowID, bounds: CGRect)] = windows.compactMap { window in
                guard pids[window.windowID] == nil else {
                    return nil
                }
                guard let bounds = window.currentBounds() else {
                    return nil
                }
                return (window.windowID, bounds)
            }
            if unresolved.isEmpty {
                return
            }

            let items = collectExtrasMenuBarItems()

            var unclaimedWindowIDs = Set(unresolved.map { $0.windowID })
            var unclaimedItemIndices = Set(items.indices)

            // Phase 1: exact resolution via the backing window, where the
            // system provides one.
            for index in items.indices {
                guard let windowID = AXHelpers.windowID(for: items[index].element) else {
                    continue
                }
                if unclaimedWindowIDs.remove(windowID) != nil {
                    pids[windowID] = items[index].pid
                    unclaimedItemIndices.remove(index)
                }
            }

            // Phase 2: score all legal geometric pairings.
            var scoredPairs = [(score: CGFloat, itemIndex: Int, windowID: CGWindowID)]()
            for (windowID, bounds) in unresolved where unclaimedWindowIDs.contains(windowID) {
                for index in unclaimedItemIndices {
                    let frame = items[index].frame
                    guard bounds.minX <= frame.midX, frame.midX <= bounds.maxX else {
                        continue
                    }
                    let score = abs(bounds.midX - frame.midX) * 10 + abs(bounds.width - frame.width)
                    scoredPairs.append((score, index, windowID))
                }
            }

            // Phase 3: claim pairs greedily, best score first, one window
            // per item and one item per window.
            for pair in scoredPairs.sorted(by: { $0.score < $1.score }) {
                guard
                    unclaimedWindowIDs.contains(pair.windowID),
                    unclaimedItemIndices.contains(pair.itemIndex)
                else {
                    continue
                }
                pids[pair.windowID] = items[pair.itemIndex].pid
                unclaimedWindowIDs.remove(pair.windowID)
                unclaimedItemIndices.remove(pair.itemIndex)
            }

            if !unclaimedWindowIDs.isEmpty {
                Logger.default.warning("Unable to attribute source PIDs for windows \(String(describing: unclaimedWindowIDs.sorted()))")
            }
        }
    }

    /// The shared cache.
    static let shared = SourcePIDCache()

    /// The cache's protected state.
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Observer for running applications.
    private lazy var cancellable = NSWorkspace.shared.publisher(for: \.runningApplications).sink { [weak self] runningApps in
        guard let self else {
            return
        }

        Logger.default.debug("Received new running applications")

        let windowIDs = Bridging.getMenuBarWindowList(option: .itemsOnly)

        state.withLock { state in
            // Convert the cached state to dictionaries keyed by pid to
            // allow for efficient repeated access.
            let appMappings = state.apps.reduce(into: [:]) { result, app in
                result[app.processIdentifier] = app
            }
            let pidMappings: [pid_t: [CGWindowID: pid_t]] = windowIDs.reduce(into: [:]) { result, windowID in
                if let pid = state.pids[windowID] {
                    result[pid, default: [:]][windowID] = pid
                }
            }

            // Create a new state that matches the current running apps.
            state = runningApps.reduce(into: State()) { result, app in
                let pid = app.processIdentifier

                if let app = appMappings[pid] {
                    // Prefer the cached app, as it may have already done
                    // the work to initialize its extras menu bar.
                    result.apps.append(app)
                } else {
                    // App wasn't in the cache, so it must be new.
                    result.apps.append(CachedApplication(app))
                }

                if let pids = pidMappings[pid] {
                    result.pids.merge(pids) { (_, new) in new }
                }
            }
        }
    }

    /// Creates the shared cache.
    private init() {
        Bridging.setProcessUnresponsiveTimeout(3)
    }

    /// Starts the observers for the cache.
    func start() {
        Logger.default.debug("Starting observers for source PID cache")
        _ = cancellable
    }

    /// Returns the cached process identifier for the given window,
    /// updating the cache if needed.
    func pid(for window: WindowInfo) -> pid_t? {
        pids(for: [window])[window.windowID]
    }

    /// Returns the cached process identifiers for the given windows,
    /// updating the cache if needed.
    ///
    /// Windows whose source process cannot be determined are omitted
    /// from the result.
    func pids(for windows: [WindowInfo]) -> [CGWindowID: pid_t] {
        state.withLock { state in
            state.updatePIDs(for: windows)
            return windows.reduce(into: [:]) { result, window in
                result[window.windowID] = state.pids[window.windowID]
            }
        }
    }
}
