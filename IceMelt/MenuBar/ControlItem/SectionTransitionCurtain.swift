//
//  SectionTransitionCurtain.swift
//  IceMelt
//

import Cocoa
import OSLog

/// Covers the menu bar with a picture of itself while a section is shown
/// or hidden in place, and slides the section's items in or out from
/// behind the visible items, on macOS 27 and later.
///
/// On macOS 27 a hidden section waits in the system overflow, left of the
/// blank stretch that hides it, so the system slides its items in from the
/// middle of the bar, left to right, and slides its « back out to the
/// middle as the section hides. Neither can be changed. The curtain hides
/// both: it holds the bar as it was until the bar has settled, then slides
/// a picture of the section's items out leftward from the visible items as
/// the section opens, or back rightward behind them as it hides, and
/// leaves the real bar showing the same thing. The curtain ignores the
/// mouse.
@available(macOS 27.0, *)
@MainActor
final class SectionTransitionCurtain {
    private static let logger = Logger(category: "SectionTransitionCurtain")

    /// How long the section's items take to slide.
    private static let slideDuration: CFTimeInterval = 0.22

    private let panel: NSPanel

    /// The bar as it stands behind the sliding items.
    private let baseLayer = CALayer()

    /// The section's items, sliding.
    private let slideLayer = CALayer()

    /// The stretch of the bar covered, in global display coordinates with
    /// the origin at the top left.
    private var rect = CGRect.zero

    /// The bar as it was when the curtain was drawn.
    private var before: CGImage?

    /// Counts curtains, so that one finishing late can tell it was replaced.
    private var generation = 0

    /// A picture of the bar taken ahead of time, and where and when.
    private var prepared: (rect: CGRect, image: CGImage, takenAt: ContinuousClock.Instant)?

    /// How long a picture taken ahead of time stays good for.
    private static let preparedLifetime = Duration.seconds(10)

    init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Above the « mask, which is part of the picture.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        panel.title = "Section Transition Curtain"
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
        let view = NSView()
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        view.layer?.addSublayer(baseLayer)
        view.layer?.addSublayer(slideLayer)
        panel.contentView = view
    }

    /// Pictures the given stretch of the menu bar as it is now, for a
    /// later curtain over the same stretch to use (see
    /// ``cover(_:usingPrepared:)``).
    func prepare(_ rect: CGRect) {
        guard !panel.isVisible, rect.width >= 1, let image = capture(rect) else {
            return
        }
        prepared = (rect, image, .now)
    }

    /// Covers the given stretch of the menu bar with a picture of it as it
    /// is now. Call it before the bar changes.
    ///
    /// - Parameters:
    ///   - rect: The stretch to cover, in global display coordinates with
    ///     the origin at the top left.
    ///   - usingPrepared: Whether to use the picture ``prepare(_:)`` took
    ///     of the same stretch, if it is recent, rather than one taken now.
    /// - Returns: Whether the bar could be pictured and is now covered.
    @discardableResult
    func cover(_ rect: CGRect, usingPrepared: Bool = false) -> Bool {
        generation += 1
        var picture: CGImage?
        if usingPrepared, let prepared, prepared.rect == rect, prepared.takenAt.duration(to: .now) < Self.preparedLifetime {
            picture = prepared.image
        }
        guard rect.width >= 1, let image = picture ?? capture(rect) else {
            Self.logger.debug("Couldn't picture the bar for a curtain")
            remove()
            return false
        }
        self.rect = rect
        before = image
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        panel.setFrame(CGRect(x: rect.minX, y: primaryMaxY - rect.maxY, width: rect.width, height: rect.height), display: false)
        withoutAnimation {
            baseLayer.frame = CGRect(origin: .zero, size: rect.size)
            baseLayer.contents = image
            slideLayer.removeAllAnimations()
            slideLayer.contents = nil
            slideLayer.frame = .zero
        }
        panel.orderFrontRegardless()
        return true
    }

    /// Slides the section's items out leftward from behind the visible
    /// items, now that the bar shows them, then removes the curtain.
    ///
    /// The whole covered stretch slides, its blank part over blank bar, so
    /// where the items begin needn't be known exactly.
    ///
    /// - Parameter distance: How far the items travel: about their width
    ///   on the bar, and at most the covered stretch's.
    func slideOpen(distance: CGFloat) {
        let current = generation
        guard panel.isVisible, let after = capture(rect), let strip = strip(of: after, from: rect.minX) else {
            remove()
            return
        }
        // The bar behind stays as it was; only the items move.
        withoutAnimation {
            slideLayer.contents = strip.image
            slideLayer.frame = strip.frame
        }
        slide(from: min(max(distance, 1), strip.frame.width), to: 0, generation: current)
    }

    /// Slides the section's items rightward behind the visible items, now
    /// that the bar has hidden them, then removes the curtain.
    ///
    /// - Parameter itemsMinX: Where the section's items began on the bar
    ///   when the curtain was drawn, in global display coordinates.
    func slideClosed(itemsMinX: CGFloat) {
        let current = generation
        guard
            panel.isVisible,
            let before,
            let after = capture(rect),
            let strip = strip(of: before, from: itemsMinX)
        else {
            remove()
            return
        }
        // The bar behind is the bar as it is now, without the items.
        withoutAnimation {
            baseLayer.contents = after
            slideLayer.contents = strip.image
            slideLayer.frame = strip.frame
        }
        slide(from: 0, to: strip.frame.width, generation: current)
    }

    /// Removes the curtain at once.
    func remove() {
        generation += 1
        panel.orderOut(nil)
    }

    /// Moves the sliding layer from one offset to the other, and removes
    /// the curtain once it gets there.
    private func slide(from startOffset: CGFloat, to endOffset: CGFloat, generation current: Int) {
        let origin = slideLayer.position.x
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == current else {
                    return
                }
                self.panel.orderOut(nil)
            }
        }
        let animation = CABasicAnimation(keyPath: "position.x")
        animation.fromValue = origin + startOffset
        animation.toValue = origin + endOffset
        animation.duration = Self.slideDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        slideLayer.add(animation, forKey: "slide")
        CATransaction.commit()
    }

    /// Returns the part of the given picture of the covered stretch that
    /// holds the section's items, from their leading edge to the visible
    /// items, with its frame in the curtain's own coordinates.
    private func strip(of image: CGImage, from itemsMinX: CGFloat) -> (image: CGImage, frame: CGRect)? {
        let localMinX = (itemsMinX - rect.minX).clamped(to: 0...rect.width)
        let width = rect.width - localMinX
        guard width >= 1 else {
            return nil
        }
        let scale = CGFloat(image.width) / rect.width
        let crop = CGRect(x: localMinX * scale, y: 0, width: width * scale, height: CGFloat(image.height))
        guard let cropped = image.cropping(to: crop.integral) else {
            return nil
        }
        return (cropped, CGRect(x: localMinX, y: 0, width: width, height: rect.height))
    }

    /// Returns a picture of the given stretch of the screen as composited,
    /// without the curtain itself.
    private func capture(_ rect: CGRect) -> CGImage? {
        let ownPanel = CGWindowID(panel.windowNumber)
        let windowIDs = WindowInfo.createWindows(option: .onScreen)
            .filter { $0.windowID != ownPanel && $0.bounds.intersects(rect) }
            .map(\.windowID)
        return ScreenCapture.captureWindows(with: windowIDs, screenBounds: rect)
    }

    /// Runs the given changes to the layers without implicit animations.
    private func withoutAnimation(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }
}
