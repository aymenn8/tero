import AppKit

// Approved geometry from assets/tero-symbol.svg (32 × 32, y downward).
func symbol(_ ctx: CGContext) {
    let path = CGMutablePath()
        path.move(to: CGPoint(x: 16, y: 2))
        path.addCurve(to: CGPoint(x: 8.3, y: 9.8), control1: CGPoint(x: 12.8, y: 2), control2: CGPoint(x: 8.3, y: 6.2))
        path.addCurve(to: CGPoint(x: 9.1, y: 13.4), control1: CGPoint(x: 8.3, y: 11.4), control2: CGPoint(x: 9.1, y: 12.6))
        path.addCurve(to: CGPoint(x: 7.5, y: 14.7), control1: CGPoint(x: 9.1, y: 14.2), control2: CGPoint(x: 8.5, y: 14.4))
        path.addCurve(to: CGPoint(x: 2, y: 21.3), control1: CGPoint(x: 3.4, y: 15.8), control2: CGPoint(x: 2, y: 18.9))
        path.addCurve(to: CGPoint(x: 9.2, y: 28), control1: CGPoint(x: 2, y: 25.1), control2: CGPoint(x: 5.2, y: 28))
        path.addCurve(to: CGPoint(x: 16, y: 24.3), control1: CGPoint(x: 12.3, y: 28), control2: CGPoint(x: 14.3, y: 24.3))
        path.addCurve(to: CGPoint(x: 22.8, y: 28), control1: CGPoint(x: 17.7, y: 24.3), control2: CGPoint(x: 19.7, y: 28))
        path.addCurve(to: CGPoint(x: 30, y: 21.3), control1: CGPoint(x: 26.8, y: 28), control2: CGPoint(x: 30, y: 25.1))
        path.addCurve(to: CGPoint(x: 24.5, y: 14.7), control1: CGPoint(x: 30, y: 18.9), control2: CGPoint(x: 28.6, y: 15.8))
        path.addCurve(to: CGPoint(x: 22.9, y: 13.4), control1: CGPoint(x: 23.5, y: 14.4), control2: CGPoint(x: 22.9, y: 14.2))
        path.addCurve(to: CGPoint(x: 23.7, y: 9.8), control1: CGPoint(x: 22.9, y: 12.6), control2: CGPoint(x: 23.7, y: 11.4))
        path.addCurve(to: CGPoint(x: 16, y: 2), control1: CGPoint(x: 23.7, y: 6.2), control2: CGPoint(x: 19.2, y: 2))
        path.closeSubpath()
        path.move(to: CGPoint(x: 16, y: 4.8))
        path.addCurve(to: CGPoint(x: 11, y: 9.8), control1: CGPoint(x: 14.1, y: 4.8), control2: CGPoint(x: 11, y: 7.7))
        path.addCurve(to: CGPoint(x: 16, y: 14.7), control1: CGPoint(x: 11, y: 12), control2: CGPoint(x: 14.2, y: 14.7))
        path.addCurve(to: CGPoint(x: 21, y: 9.8), control1: CGPoint(x: 17.8, y: 14.7), control2: CGPoint(x: 21, y: 12))
        path.addCurve(to: CGPoint(x: 16, y: 4.8), control1: CGPoint(x: 21, y: 7.7), control2: CGPoint(x: 17.9, y: 4.8))
        path.closeSubpath()
        path.move(to: CGPoint(x: 10.2, y: 16.2))
        path.addCurve(to: CGPoint(x: 4.8, y: 21.3), control1: CGPoint(x: 7.7, y: 16.2), control2: CGPoint(x: 4.8, y: 18.7))
        path.addCurve(to: CGPoint(x: 9.2, y: 25.6), control1: CGPoint(x: 4.8, y: 23.6), control2: CGPoint(x: 6.9, y: 25.6))
        path.addCurve(to: CGPoint(x: 14.4, y: 20.6), control1: CGPoint(x: 11.5, y: 25.6), control2: CGPoint(x: 14.4, y: 22.7))
        path.addCurve(to: CGPoint(x: 10.2, y: 16.2), control1: CGPoint(x: 14.4, y: 18.6), control2: CGPoint(x: 12.6, y: 16.2))
        path.closeSubpath()
        path.move(to: CGPoint(x: 21.8, y: 16.2))
        path.addCurve(to: CGPoint(x: 17.6, y: 20.6), control1: CGPoint(x: 19.4, y: 16.2), control2: CGPoint(x: 17.6, y: 18.6))
        path.addCurve(to: CGPoint(x: 22.8, y: 25.6), control1: CGPoint(x: 17.6, y: 22.7), control2: CGPoint(x: 20.5, y: 25.6))
        path.addCurve(to: CGPoint(x: 27.2, y: 21.3), control1: CGPoint(x: 25.1, y: 25.6), control2: CGPoint(x: 27.2, y: 23.6))
        path.addCurve(to: CGPoint(x: 21.8, y: 16.2), control1: CGPoint(x: 27.2, y: 18.7), control2: CGPoint(x: 24.3, y: 16.2))
        path.closeSubpath()
    ctx.addPath(path)
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fillPath(using: .evenOdd)
}
func context(_ size: Int) -> CGContext {
    CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
// A high-contrast label distinguishes development builds even in the Dock.
func devBadge(_ ctx: CGContext) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSColor(srgbRed: 1, green: 0.52, blue: 0.16, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 276, y: 116, width: 472, height: 174), xRadius: 48, yRadius: 48).fill()
    let label = NSAttributedString(string: "DEV", attributes: [.font: NSFont.systemFont(ofSize: 118, weight: .heavy), .foregroundColor: NSColor(white: 0.07, alpha: 1), .kern: 7])
    label.draw(at: NSPoint(x: (1024 - label.size().width) / 2, y: 203 - label.size().height / 2))
    NSGraphicsContext.restoreGraphicsState()
}
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
try Data("{\"info\":{\"author\":\"xcode\",\"version\":1}}\n".utf8).write(to: root.appendingPathComponent("Contents.json"))
for dev in [false, true] {
    let folder = root.appendingPathComponent(dev ? "DevAppIcon.appiconset" : "AppIcon.appiconset")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let ctx = context(1024)
    let tile = CGPath(roundedRect: CGRect(x: 64, y: 64, width: 896, height: 896), cornerWidth: 200, cornerHeight: 200, transform: nil)
    ctx.addPath(tile); ctx.setFillColor(CGColor(gray: 0.045, alpha: 1)); ctx.fillPath()
    ctx.saveGState(); ctx.translateBy(x: 0, y: 1024); ctx.scaleBy(x: 1, y: -1)
    ctx.translateBy(x: dev ? 224 : 192, y: dev ? 150 : 222); ctx.scaleBy(x: dev ? 18 : 20, y: dev ? 18 : 20)
    symbol(ctx)
    ctx.restoreGState()
    if dev {
        devBadge(ctx)
    }
    let image = ctx.makeImage()!
    // A native layered icon prevents macOS from framing the legacy bitmap.
    let native = root.deletingLastPathComponent().appendingPathComponent(dev ? "DevTeroIcon.icon" : "TeroIcon.icon")
    let assets = native.appendingPathComponent("Assets")
    try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
    let foreground = context(1024)
    foreground.translateBy(x: 0, y: 1024); foreground.scaleBy(x: 1, y: -1)
    foreground.translateBy(x: dev ? 224 : 192, y: dev ? 150 : 222); foreground.scaleBy(x: dev ? 18 : 20, y: dev ? 18 : 20)
    symbol(foreground)
    if dev {
        foreground.resetClip()
        foreground.concatenate(foreground.ctm.inverted())
        devBadge(foreground)
    }
    try NSBitmapImageRep(cgImage: foreground.makeImage()!).representation(using: .png, properties: [:])!.write(to: assets.appendingPathComponent("symbol.png"))
    let nativeContents: [String:Any] = [
        "fill": ["automatic-gradient":"extended-gray:0.04500,1.00000"],
        "groups": [["layers": [["image-name":"symbol.png", "name":"Tero", "glass":false]],
                    "shadow":["kind":"neutral", "opacity":0],
                    "translucency":["enabled":false,"value":0]]],
        "supported-platforms":["squares":["macOS"]]
    ]
    try JSONSerialization.data(withJSONObject: nativeContents, options: [.prettyPrinted,.sortedKeys]).write(to: native.appendingPathComponent("icon.json"))
    var entries: [[String:String]] = []
    for pointSize in [16,32,128,256,512] {
        for scale in [1,2] {
            let pixels = pointSize * scale
            let scaled = context(pixels); scaled.interpolationQuality = .high
            scaled.draw(image, in: CGRect(x: 0,y: 0,width: pixels,height: pixels))
            let data = NSBitmapImageRep(cgImage: scaled.makeImage()!).representation(using: .png, properties: [:])!
            let name = "icon_\(pointSize)x\(pointSize)\(scale == 2 ? "@2x" : "").png"
            try data.write(to: folder.appendingPathComponent(name))
            entries.append(["idiom":"mac","size":"\(pointSize)x\(pointSize)","scale":"\(scale)x","filename":name])
        }
    }
    let contents: [String:Any] = ["images":entries,"info":["author":"xcode","version":1]]
    try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted,.sortedKeys]).write(to: folder.appendingPathComponent("Contents.json"))
}
