import AppKit
import CoreText

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let root = URL(fileURLWithPath: CommandLine.arguments[2])
CTFontManagerRegisterFontsForURL(root.appendingPathComponent("Assets/Fonts/InterVariable.ttf") as CFURL, .process, nil)
let symbol = NSImage(contentsOf: root.appendingPathComponent("Resources/TeroIcon.icon/Assets/symbol.png"))!
var images: [NSBitmapImageRep] = []
for scale in [1, 2] {
    let pixels = 660 * scale
    let ctx = CGContext(data: nil, width: pixels, height: 420 * scale, bitsPerComponent: 8, bytesPerRow: pixels * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    // Finder uses black file labels over image backgrounds, even in Dark Mode.
    NSColor(white: 0.955, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: 660, height: 420)).fill()
    func text(_ value: String, y: CGFloat, size: CGFloat, color: CGFloat, weight: NSFont.Weight = .regular) {
        let font = NSFont(name: "Inter", size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)
        let label = NSAttributedString(string: value, attributes: [.font:font, .foregroundColor:NSColor(white: color, alpha: 1)])
        label.draw(at: NSPoint(x: (660-label.size().width)/2, y: 420-y-label.size().height))
    }
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    symbol.draw(in: NSRect(x: 311, y: 358, width: 38, height: 38))
    ctx.setBlendMode(.sourceIn)
    ctx.setFillColor(NSColor(white: 0.12, alpha: 1).cgColor)
    ctx.fill(CGRect(x: 311, y: 358, width: 38, height: 38))
    ctx.endTransparencyLayer()
    ctx.setBlendMode(.normal)
    text("Install Tero", y: 75, size: 25, color: 0.12, weight: .semibold)
    text("Drag Tero into Applications.", y: 114, size: 13, color: 0.42)
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 303, y: 193)); arrow.line(to: NSPoint(x: 357, y: 193))
    arrow.move(to: NSPoint(x: 348, y: 202)); arrow.line(to: NSPoint(x: 357, y: 193)); arrow.line(to: NSPoint(x: 348, y: 184))
    NSColor(white: 0.48, alpha: 1).setStroke(); arrow.lineWidth = 1.6; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round; arrow.stroke()
    text("macOS 14 or later  ·  Beta", y: 134, size: 10, color: 0.43)
    NSGraphicsContext.restoreGraphicsState()
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    rep.size = NSSize(width: 660, height: 420)
    images.append(rep)
}
try NSBitmapImageRep.representationOfImageReps(in: images, using: .tiff, properties: [:])!.write(to: output)
