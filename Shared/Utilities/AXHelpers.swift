//
//  AXHelpers.swift
//  Shared
//

import AXSwift
import Cocoa

enum AXHelpers {
    private static let queue = DispatchQueue.targetingGlobal(
        label: "AXHelpers.queue",
        qos: .userInteractive,
        attributes: .concurrent
    )

    @discardableResult
    static func isProcessTrusted(prompt: Bool = false) -> Bool {
        queue.sync { checkIsProcessTrusted(prompt: prompt) }
    }

    static func element(at point: CGPoint) -> UIElement? {
        queue.sync { try? systemWideElement.elementAtPosition(Float(point.x), Float(point.y)) }
    }

    static func application(for runningApp: NSRunningApplication) -> Application? {
        queue.sync { Application(runningApp) }
    }

    static func extrasMenuBar(for app: Application) -> UIElement? {
        queue.sync { try? app.attribute(.extrasMenuBar) }
    }

    static func children(for element: UIElement) -> [UIElement] {
        queue.sync { try? element.arrayAttribute(.children) } ?? []
    }

    static func isEnabled(_ element: UIElement) -> Bool {
        queue.sync { try? element.attribute(.enabled) } ?? false
    }

    static func frame(for element: UIElement) -> CGRect? {
        queue.sync { try? element.attribute(.frame) }
    }

    static func role(for element: UIElement) -> Role? {
        queue.sync { try? element.role() }
    }

    /// Returns the identifier of the window backing the given element, if the
    /// system has a mapping for it. Returns `nil` for most menu bar items as
    /// of macOS 26 (see `_AXUIElementGetWindow`).
    static func windowID(for element: UIElement) -> CGWindowID? {
        queue.sync {
            var windowID = CGWindowID(0)
            guard
                _AXUIElementGetWindow(element.element, &windowID) == .success,
                windowID != 0
            else {
                return nil
            }
            return windowID
        }
    }

    /// Sets the timeout for accessibility messages sent to the given element.
    static func setMessagingTimeout(_ seconds: Float, for element: UIElement) {
        queue.sync { AXUIElementSetMessagingTimeout(element.element, seconds) }
    }
}
