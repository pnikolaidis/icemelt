//
//  MenuBarFreezePanel.swift
//  IceMelt
//

import Cocoa

/// A panel that holds a stretch of the menu bar still while the system
/// reflows it (macOS 27).
///
/// Moving a hosted item means expanding the system overflow, which lays
/// every hidden item out left of the notch, and sometimes collapsing the
/// dividers, which floods the bar with them; each step reflows the bar in
/// view. The panel captures the stretch of the bar the move will disturb
/// and shows those pixels over it, above the agent's items, until the bar
/// has settled, so the user sees only the result.
@MainActor
final class MenuBarFreezePanel: NSPanel {
    /// Covers the given rect, in screen coordinates with the origin at the
    /// top left of the main display, with an image of what is there now.
    ///
    /// Returns `nil` when the screen can't be captured, in which case the
    /// move simply runs in view.
    static func cover(_ rect: CGRect) -> MenuBarFreezePanel? {
        guard
            rect.width > 1,
            ScreenCapture.cachedCheckPermissions(),
            let main = NSScreen.screens.first,
            let image = ScreenCapture.captureWindows(
                with: Bridging.getWindowList(option: .onScreen),
                screenBounds: rect,
                option: .bestResolution
            )
        else {
            return nil
        }
        let frame = NSRect(x: rect.minX, y: main.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        let panel = MenuBarFreezePanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar + 1
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isExcludedFromWindowsMenu = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone, .ignoresCycle, .stationary]
        let view = NSImageView(frame: NSRect(origin: .zero, size: frame.size))
        view.imageScaling = .scaleAxesIndependently
        view.image = NSImage(cgImage: image, size: frame.size)
        panel.contentView = view
        panel.orderFrontRegardless()
        return panel
    }

    /// Removes the panel.
    func lift() {
        orderOut(nil)
    }
}
