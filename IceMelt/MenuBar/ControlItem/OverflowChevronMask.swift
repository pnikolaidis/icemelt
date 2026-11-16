//
//  OverflowChevronMask.swift
//  IceMelt
//

import Cocoa
import OSLog

/// Covers the system's overflow « with a blank stretch of the menu bar
/// beside it, on macOS 27 and later.
///
/// The system's « leads the items on the bar, so on a display too wide for
/// one divider it sits at the far end of the blank stretch that hides the
/// section, half a screen from the visible items. The hidden divider draws
/// IceMelt's own « beside the visible items instead (see
/// `ControlItem.updateHostedHidingMarker()`), and the mask keeps the two
/// from showing at once. With the section shown, the open overflow's »
/// sits against the divider's own <, and the mask covers the » instead.
/// The mask ignores the mouse, so a click on the covered chevron still
/// reaches it.
@available(macOS 27.0, *)
@MainActor
final class OverflowChevronMask {
    /// A mask panel and what it currently shows.
    private struct Mask {
        let panel: NSPanel
        let imageView: NSImageView
        var frame: CGRect?
        var capturedAt: ContinuousClock.Instant?

        /// Whether the current cover may be restored once uncovered.
        var isRestorable = false

        /// Where the mask last covered the « with the section hidden, and
        /// what with, kept since.
        var lastFrame: CGRect?
        var lastImage: NSImage?
    }

    /// How long a capture is reused while the « holds still. The bar's look
    /// changes with the wallpaper and the appearance, without notice, so it
    /// is captured afresh now and then.
    private static let captureLifetime = Duration.seconds(5)

    private static let logger = Logger(category: "OverflowChevronMask")

    /// Owners of full-screen windows at the menu bar's own level that
    /// aren't part of the bar, such as the screenshot overlay, which dims
    /// or freezes the screen beneath it.
    private static let overlayOwners: Set<String> = ["Screenshot", "screencaptureui"]

    /// The mask panels, keyed by display.
    private var masks = [CGDirectDisplayID: Mask]()

    /// How far the cover fades out at its edges.
    private static let featherWidth: CGFloat = 2

    /// Where to cover the « on one display, and the blank stretch of the
    /// bar to cover it with, both in global display coordinates with the
    /// origin at the top left.
    struct Target: Equatable {
        /// The «'s frame on the bar.
        let chevron: CGRect

        /// Whether the blank stretch to cover the « with lies right of it,
        /// rather than left of it.
        let samplesRight: Bool

        /// Whether ``OverflowChevronMask/restoreLastCover()`` may cover the
        /// « here again. Only a cover made with the section hidden may be:
        /// the « returns there as the section hides.
        let isRestorable: Bool

        /// The stretch covered: a band around the « glyph, short of the
        /// bar's top and bottom. The system shades the bar toward its
        /// bottom edge after compositing, so no capture shows the shading,
        /// and a cover reaching there shows as a lighter patch.
        var frame: CGRect {
            CGRect(x: chevron.minX - 2, y: chevron.midY - 7, width: chevron.width + 4, height: 15)
        }

        /// The blank stretch of the bar to cover the « with.
        var sample: CGRect {
            frame.offsetBy(dx: samplesRight ? frame.width + 2 : -(frame.width + 2), dy: 0)
        }
    }

    /// Covers the « on each of the given displays, and uncovers it on
    /// every other display.
    func update(covering targets: [CGDirectDisplayID: Target]) {
        for displayID in masks.keys where targets[displayID] == nil {
            uncover(on: displayID)
        }
        for (displayID, target) in targets {
            cover(target, on: displayID)
        }
    }

    /// Uncovers the « on every display.
    func uncoverAll() {
        for displayID in masks.keys {
            uncover(on: displayID)
        }
    }

    /// Covers the target's « with a capture of its blank stretch, or
    /// uncovers the display if the bar can't be captured.
    ///
    /// The bar is captured as composited, IceMelt's own windows left out,
    /// rather than from the wallpaper window: on macOS 27 that window
    /// captures blank, and the bar's own material differs from it anyway.
    private func cover(_ target: Target, on displayID: CGDirectDisplayID) {
        var mask = masks[displayID] ?? Self.makeMask()
        let frame = target.frame
        let now = ContinuousClock.now
        let isFresh = mask.capturedAt.map { $0.duration(to: now) < Self.captureLifetime } ?? false
        // A press on the divider highlights its blank stretch, which the
        // capture would then keep.
        let isPressing = NSEvent.pressedMouseButtons != 0
        if mask.frame != frame || (!isFresh && !isPressing) {
            let ownPID = ProcessInfo.processInfo.processIdentifier
            let windowIDs = WindowInfo.createWindows(option: .onScreen)
                .filter { window in
                    window.ownerPID != ownPID &&
                    window.layer <= Int(CGWindowLevelForKey(.statusWindow)) &&
                    !Self.overlayOwners.contains(window.ownerName ?? "") &&
                    window.bounds.intersects(target.sample)
                }
                .map(\.windowID)
            guard let image = ScreenCapture.captureWindows(with: windowIDs, screenBounds: target.sample) else {
                Self.logger.debug("Couldn't capture the bar to cover the « with on display \(displayID, privacy: .public)")
                masks[displayID] = mask
                uncover(on: displayID)
                return
            }
            mask.imageView.image = NSImage(cgImage: Self.feathered(image, scale: CGFloat(image.width) / frame.width), size: frame.size)
            mask.capturedAt = now
        }
        if mask.frame != frame {
            mask.panel.setFrame(Self.appKitFrame(for: frame), display: true)
            mask.frame = frame
        }
        mask.isRestorable = target.isRestorable
        if target.isRestorable {
            mask.lastFrame = frame
            mask.lastImage = mask.imageView.image
        }
        mask.panel.orderFrontRegardless()
        masks[displayID] = mask
    }

    /// Uncovers the « on the given display.
    private func uncover(on displayID: CGDirectDisplayID) {
        guard var mask = masks[displayID] else {
            return
        }
        mask.panel.orderOut(nil)
        mask.frame = nil
        masks[displayID] = mask
    }

    /// Covers the « again where it was last covered with the section
    /// hidden, at once.
    ///
    /// A hiding section brings the « back where it was before the section
    /// was shown, and the next read of the bar, which places the mask
    /// exactly, comes a moment later. Without this the « shows meanwhile.
    /// A cover over the open overflow's » moves there too.
    func restoreLastCover() {
        for (displayID, var mask) in masks where mask.frame == nil || !mask.isRestorable {
            guard let frame = mask.lastFrame, let image = mask.lastImage else {
                continue
            }
            if mask.frame != frame {
                mask.panel.setFrame(Self.appKitFrame(for: frame), display: false)
            }
            mask.imageView.image = image
            mask.panel.orderFrontRegardless()
            mask.frame = frame
            mask.isRestorable = true
            masks[displayID] = mask
        }
    }

    /// Returns the given image fading out over ``featherWidth`` points at
    /// each edge, so that the cover has no hard edge where it meets the bar.
    private static func feathered(_ image: CGImage, scale: CGFloat) -> CGImage {
        let width = image.width
        let height = image.height
        let edge = max(featherWidth * scale, 1)
        var alpha = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            let fromY = min(CGFloat(y) + 0.5, CGFloat(height - y) - 0.5) / edge
            for x in 0..<width {
                let fromX = min(CGFloat(x) + 0.5, CGFloat(width - x) - 0.5) / edge
                alpha[y * width + x] = UInt8(min(fromX, fromY, 1) * 255)
            }
        }
        guard
            let provider = CGDataProvider(data: Data(alpha) as CFData),
            let maskImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            ),
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return image
        }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.clip(to: bounds, mask: maskImage)
        context.draw(image, in: bounds)
        return context.makeImage() ?? image
    }

    /// Converts a frame from global display coordinates to AppKit's, whose
    /// origin is at the bottom left of the primary display.
    private static func appKitFrame(for frame: CGRect) -> CGRect {
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: frame.minX, y: primaryMaxY - frame.maxY, width: frame.width, height: frame.height)
    }

    /// Creates a borderless panel, above the menu bar and click-through,
    /// that shows an image edge to edge.
    private static func makeMask() -> Mask {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.title = "Overflow Chevron Mask"
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.isExcludedFromWindowsMenu = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone, .ignoresCycle, .stationary]
        let imageView = NSImageView()
        imageView.imageScaling = .scaleAxesIndependently
        panel.contentView = imageView
        return Mask(panel: panel, imageView: imageView)
    }
}
