//
//  MouseHelpers.swift
//  IceMelt
//

import CoreGraphics
import Foundation
import OSLog

/// A namespace for mouse helper operations.
enum MouseHelpers {
    /// Returns the location of the mouse cursor in the coordinate
    /// space used by `AppKit`, with the origin at the bottom left
    /// of the screen.
    static var locationAppKit: CGPoint? {
        CGEvent(source: nil)?.unflippedLocation
    }

    /// Returns the location of the mouse cursor in the coordinate
    /// space used by `CoreGraphics`, with the origin at the top left
    /// of the screen.
    static var locationCoreGraphics: CGPoint? {
        CGEvent(source: nil)?.location
    }

    /// The number of hides currently in effect that have not yet been
    /// balanced by a show. Only ever touched on the main thread.
    private static var hideCount = 0

    /// Timer that releases the cursor if a hide is never balanced.
    private static var cursorWatchdog: Timer?

    /// How long the cursor may stay hidden before the watchdog forces
    /// it back.
    ///
    /// Comfortably longer than any legitimate item operation — a move
    /// retries up to 8 times — and far shorter than "until the user
    /// restarts IceMelt", which is what an unbalanced hide used to mean.
    private static let cursorWatchdogTimeout: TimeInterval = 10

    /// Hides the mouse cursor and increments the hide cursor count.
    ///
    /// The hide cursor count is tracked per window server connection,
    /// and connections are created per thread. Both this function and
    /// ``showCursor()`` dispatch to the main thread so that every
    /// hide/show pair lands on the same connection — a pair split
    /// across cooperative pool threads leaks a hide count that takes
    /// effect the next time the app is activated. The main thread's
    /// connection is also the one that carries the
    /// `SetsCursorInBackground` property set at launch.
    ///
    /// Balance is not enough on its own: every caller pairs its hide
    /// with a `defer` that runs on return, so a caller that blocks
    /// indefinitely leaves the cursor hidden for as long as it blocks.
    /// The watchdog started here bounds that (issue #35).
    static func hideCursor() {
        DispatchQueue.main.async {
            let result = CGDisplayHideCursor(CGMainDisplayID())
            guard result == .success else {
                Logger.default.error("CGDisplayHideCursor failed with error \(result.logString, privacy: .public)")
                return
            }
            hideCount += 1
            restartCursorWatchdog()
        }
    }

    /// Decrements the hide cursor count and shows the mouse cursor
    /// if the count is `0`.
    ///
    /// Dispatched to the main thread for the reasons described in
    /// ``hideCursor()``.
    static func showCursor() {
        DispatchQueue.main.async {
            let result = CGDisplayShowCursor(CGMainDisplayID())
            if result != .success {
                Logger.default.error("CGDisplayShowCursor failed with error \(result.logString, privacy: .public)")
            }
            hideCount = max(0, hideCount - 1)
            if hideCount == 0 {
                cursorWatchdog?.invalidate()
                cursorWatchdog = nil
            } else {
                restartCursorWatchdog()
            }
        }
    }

    /// Restarts the watchdog that forces the cursor back if the
    /// outstanding hides are never balanced.
    ///
    /// Must be called on the main thread.
    private static func restartCursorWatchdog() {
        cursorWatchdog?.invalidate()
        cursorWatchdog = Timer.scheduledTimer(withTimeInterval: cursorWatchdogTimeout, repeats: false) { _ in
            guard hideCount > 0 else {
                cursorWatchdog = nil
                return
            }
            Logger.default.error(
                """
                Cursor still hidden after \(cursorWatchdogTimeout, format: .fixed(precision: 0), privacy: .public)s \
                with \(hideCount, privacy: .public) unbalanced hide(s); forcing it back
                """
            )
            // Drain the count rather than showing once: the count is
            // per connection, and only reaching 0 makes the cursor visible.
            while hideCount > 0 {
                let result = CGDisplayShowCursor(CGMainDisplayID())
                if result != .success {
                    Logger.default.error("CGDisplayShowCursor failed with error \(result.logString, privacy: .public)")
                    break
                }
                hideCount -= 1
            }
            cursorWatchdog = nil
        }
    }

    /// Moves the mouse cursor to the given point without generating
    /// events.
    ///
    /// - Parameter point: The point to move the cursor to in global
    ///   display coordinates.
    static func warpCursor(to point: CGPoint) {
        let result = CGWarpMouseCursorPosition(point)
        if result != .success {
            Logger.default.error("CGWarpMouseCursorPosition failed with error \(result.logString, privacy: .public)")
        }
    }

    /// Connects or disconnects the positions of the mouse and cursor.
    ///
    /// - Parameter connected: A Boolean value that determines whether
    ///   to connect or disconnect the positions.
    static func associateMouseAndCursor(_ connected: Bool) {
        let result = CGAssociateMouseAndMouseCursorPosition(connected ? 1 : 0)
        if result != .success {
            Logger.default.error("CGAssociateMouseAndMouseCursorPosition failed with error \(result.logString, privacy: .public)")
        }
    }

    /// Returns a Boolean value that indicates whether a mouse button
    /// is pressed.
    ///
    /// - Parameter button: The mouse button to check. Pass `nil` to
    ///   check all available mouse buttons (Quartz supports up to 32).
    static func isButtonPressed(_ button: CGMouseButton? = nil) -> Bool {
        let stateID = CGEventSourceStateID.combinedSessionState
        if let button {
            return CGEventSource.buttonState(stateID, button: button)
        }
        for n: UInt32 in 0...31 {
            guard
                let button = CGMouseButton(rawValue: n),
                CGEventSource.buttonState(stateID, button: button)
            else {
                continue
            }
            return true
        }
        return false
    }

    /// Returns a Boolean value that indicates whether the last mouse
    /// movement event occurred within the given duration.
    ///
    /// - Parameter duration: The duration within which the last mouse
    ///   movement event must have occurred in order to return `true`.
    static func lastMovementOccurred(within duration: Duration) -> Bool {
        let stateID = CGEventSourceStateID.combinedSessionState
        let seconds = CGEventSource.secondsSinceLastEventType(stateID, eventType: .mouseMoved)
        return .seconds(seconds) <= duration
    }

    /// Returns a Boolean value that indicates whether the last scroll
    /// wheel event occurred within the given duration.
    ///
    /// - Parameter duration: The duration within which the last scroll
    ///   wheel event must have occurred in order to return `true`.
    static func lastScrollWheelOccurred(within duration: Duration) -> Bool {
        let stateID = CGEventSourceStateID.combinedSessionState
        let seconds = CGEventSource.secondsSinceLastEventType(stateID, eventType: .scrollWheel)
        return .seconds(seconds) <= duration
    }
}
