// Renders the DMG background (dmg/background.tiff): a pale ice field matching
// the app icon, a drag arrow between the two icon positions, and a caption.
// Regenerate with:  swift scripts/make-dmg-background.swift
//
// Geometry is the Scratch Itch fleet standard, shared with cmdtab, hostbar,
// moonphase, olympus, iCloudWatch and fnmute: a 640x400 background under a
// {400, 120, 1040, 548} window, app icon centered at (160, 190) and the
// Applications symlink at (480, 190). Finder measures y from the top of the
// window; AppKit draws from the bottom, hence the 400 - y conversions below.
// Icon positions must match the AppleScript layout in scripts/make-dmg.sh.
//
// The colors are IceMelt's own: the icon is a pale blue droplet on a near-white
// field, so this background is light where the fleet's darker-icon apps are
// dark. Sampled from AppIcon: #E5E5E5, #D8E5E5, #CCD8E5, #B2CCE5.
import AppKit

let size = NSSize(width: 640, height: 400)

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size // 72dpi * scale — tiffutil tags the @2x variant

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Pale ice field, cool and very light, echoing the icon's backdrop.
    let bounds = NSRect(origin: .zero, size: size)
    NSColor(calibratedRed: 0.855, green: 0.894, blue: 0.925, alpha: 1).setFill()
    bounds.fill()

    // Soft lift behind the icon wells so the two 128pt icons sit on something.
    let glow = NSGradient(
        starting: NSColor(calibratedWhite: 1, alpha: 0.40),
        ending: NSColor(calibratedWhite: 1, alpha: 0))!
    glow.draw(in: NSBezierPath(ovalIn: NSRect(x: -160, y: 40, width: 960, height: 560)),
              relativeCenterPosition: .zero)

    // Drag arrow between the icon wells, in the icon's deeper blue.
    let arrow = NSBezierPath()
    arrow.lineWidth = 10
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    let y: CGFloat = 210 // icon centers sit at Finder y=190 → bottom-origin y=210
    arrow.move(to: NSPoint(x: 250, y: y))
    arrow.line(to: NSPoint(x: 380, y: y))
    arrow.move(to: NSPoint(x: 348, y: y + 26))
    arrow.line(to: NSPoint(x: 380, y: y))
    arrow.line(to: NSPoint(x: 348, y: y - 26))
    NSColor(calibratedRed: 0.404, green: 0.545, blue: 0.667, alpha: 1).setStroke()
    arrow.stroke()

    // Caption under the wells.
    let caption = "Drag IceMelt into Applications"
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 17, weight: .medium),
        .foregroundColor: NSColor(calibratedRed: 0.302, green: 0.404, blue: 0.502, alpha: 1),
        .paragraphStyle: style,
    ]
    caption.draw(in: NSRect(x: 0, y: 58, width: size.width, height: 30), withAttributes: attrs)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let outDir = URL(fileURLWithPath: "dmg")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
for (scale, name) in [(CGFloat(1), "background.png"), (2, "background@2x.png")] {
    let rep = render(scale: scale)
    try! rep.representation(using: .png, properties: [:])!
        .write(to: outDir.appendingPathComponent(name))
}
print("wrote dmg/background.png and dmg/background@2x.png — combine with:")
print("  tiffutil -cathidpicheck dmg/background.png dmg/background@2x.png -out dmg/background.tiff")
