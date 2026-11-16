//
//  MenuBarAllowlist.swift
//  IceMelt
//

import AppKit
import OSLog

/// Hides apps' menu bar items by leaving them off the list of apps the
/// menu bar draws, on macOS 27 and later.
///
/// macOS 27 draws every status item in one system process, and an item
/// hides only by overflowing behind the system's «. A section hidden that
/// way needs a blank stretch the width of the bar, and leaves the « at its
/// far end. MenuBarClientCore, the private framework behind the system's
/// exam lockdown mode, can instead restrict the menu bar to an allowlist
/// of apps: the others aren't drawn at all, and come back where they were
/// once the restriction ends. It works per app, not per item, and never
/// hides the system's own items. The restriction ends with the process,
/// however that ends.
@available(macOS 27.0, *)
@MainActor
final class MenuBarAllowlist {
    private static let logger = Logger(category: "MenuBarAllowlist")

    private static let frameworkPath = "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore"

    /// The configuration and assertion classes, or `nil` if the framework
    /// doesn't have them.
    private static let classes: (configuration: NSObject.Type, assertion: NSObject.Type)? = {
        guard
            dlopen(frameworkPath, RTLD_NOW) != nil,
            let configuration = NSClassFromString("MBAssessmentModeConfiguration") as? NSObject.Type,
            let assertion = NSClassFromString("MBAssessmentModeAssertion") as? NSObject.Type,
            configuration.instancesRespond(to: initSelector),
            assertion.instancesRespond(to: activateSelector),
            assertion.instancesRespond(to: invalidateSelector)
        else {
            logger.error("MenuBarClientCore's allowlist isn't available")
            return nil
        }
        return (configuration, assertion)
    }()

    private static let initSelector = NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:")
    private static let activateSelector = NSSelectorFromString("activateWithConfiguration:completionHandler:")
    private static let invalidateSelector = NSSelectorFromString("invalidate")

    /// The system's own items, by kind. All of them stay: fewer leaves
    /// some, such as Screen Mirroring, off the bar.
    private static let systemItems = (0...255).map { NSNumber(value: $0) }

    /// Whether the allowlist can be used on this system.
    static var isAvailable: Bool {
        classes != nil
    }

    /// The active restriction, if any.
    private var assertion: NSObject?

    /// The bundle identifiers of the apps currently left off the bar.
    private(set) var hiddenBundleIDs = Set<String>()

    private var launchObserver: NSObjectProtocol?

    init() {
        // A restriction allows only the apps it lists, so an app launched
        // while one is active would be left off the bar too.
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.hiddenBundleIDs.isEmpty else {
                    return
                }
                self.activate(hiding: self.hiddenBundleIDs)
            }
        }
    }

    deinit {
        if let launchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(launchObserver)
        }
    }

    /// Leaves the given apps off the menu bar, and draws every other app.
    /// An empty set ends the restriction.
    func hide(_ bundleIDs: Set<String>) {
        guard bundleIDs != hiddenBundleIDs else {
            return
        }
        if bundleIDs.isEmpty {
            invalidate()
        } else {
            activate(hiding: bundleIDs)
        }
    }

    /// Draws every app on the menu bar again.
    func showAll() {
        invalidate()
    }

    private func activate(hiding bundleIDs: Set<String>) {
        guard let classes = Self.classes else {
            return
        }
        var allowed = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        allowed.subtract(bundleIDs)
        // IceMelt's own items must stay, or its divider goes with the rest.
        if let ownID = Bundle.main.bundleIdentifier {
            allowed.insert(ownID)
        }

        typealias InitFunction = @convention(c) (AnyObject, Selector, NSArray, NSArray) -> AnyObject
        typealias ActivateFunction = @convention(c) (AnyObject, Selector, AnyObject, @escaping @convention(block) (NSError?) -> Void) -> Void

        guard
            let allocated = classes.configuration.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
            let initIMP = class_getMethodImplementation(classes.configuration, Self.initSelector),
            let activateIMP = class_getMethodImplementation(classes.assertion, Self.activateSelector)
        else {
            Self.logger.error("Couldn't create an allowlist configuration")
            return
        }
        let initialize = unsafeBitCast(initIMP, to: InitFunction.self)
        // The framework requires arrays here, not sets.
        let configuration = initialize(allocated, Self.initSelector, Self.systemItems as NSArray, Array(allowed) as NSArray)

        // A new assertion replaces the old one only once it's active, so the
        // bar never shows everything in between.
        let previous = assertion
        let next = classes.assertion.init()
        let activate = unsafeBitCast(activateIMP, to: ActivateFunction.self)
        activate(next, Self.activateSelector, configuration) { error in
            if let error {
                Self.logger.error("Couldn't restrict the menu bar: \(error, privacy: .public)")
            }
            DispatchQueue.main.async {
                previous?.perform(Self.invalidateSelector)
            }
        }
        assertion = next
        hiddenBundleIDs = bundleIDs
        Self.logger.debug("Leaving \(bundleIDs.sorted(), privacy: .public) off the menu bar")
    }

    private func invalidate() {
        guard let assertion else {
            return
        }
        assertion.perform(Self.invalidateSelector)
        self.assertion = nil
        hiddenBundleIDs = []
        Self.logger.debug("Drawing every app on the menu bar")
    }
}
