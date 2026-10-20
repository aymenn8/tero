import SwiftUI

/// Approved connected three-bubble symbol, shared with the website and app icons.
struct TeroLogoMark: View {
    var size: CGFloat = 14

    var body: some View {
        Path(Self.symbolPath())
            .applying(CGAffineTransform(scaleX: size / 32, y: size / 32))
            .fill(.white, style: FillStyle(eoFill: true))
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Load the embedded icon directly so development rebuilds bypass Finder's icon cache.
    static var appIcon: NSImage {
        let name = Bundle.main.isTeroDevBuild ? "DevTeroIcon" : "TeroIcon"
        if let url = Bundle.main.url(forResource: name, withExtension: "icns"),
           let image = NSImage(contentsOf: url) { return image }
        return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }

    /// Coordinates match assets/tero-symbol.svg; y increases downward.
    nonisolated static func symbolPath() -> CGPath {
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
        return path
    }
}

extension Bundle {
    /// The development flavour, which unlocks developer menus and CLI fixture modes.
    var isTeroDevBuild: Bool { bundleIdentifier == "com.aymenkadri.tero.dev" }
}
