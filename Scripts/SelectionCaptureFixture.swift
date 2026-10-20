import AppKit
import WebKit

// Synthetic AX server: delayed selected-text responses reproduce optional context
// lowering the required validation timeout from 150 ms to 40 ms.
@MainActor final class SlowTextView: NSTextView {
  var transient = false
  var rangeOnly = false
  private var reads = 0
  override func accessibilitySelectedText() -> String? {
    if rangeOnly { return nil }
    reads += 1
    Thread.sleep(forTimeInterval: transient && reads == 1 ? 0.2 : 0.08)
    return super.accessibilitySelectedText()
  }
}

@MainActor final class FixtureDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
  private var window: NSWindow?
  private var readyPath: String?
  func applicationDidFinishLaunching(_ notification: Notification) {
    guard CommandLine.arguments.count == 3 else { exit(1) }
    let scenario = CommandLine.arguments[1]
    let window = NSWindow(contentRect: NSRect(x: 500, y: 350, width: 420, height: 140),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "Tero synthetic selection fixture"
    self.window = window
    let view: NSView
    if scenario == "web-reading" {
      let web = WKWebView(frame: NSRect(x: 20, y: 20, width: 380, height: 90))
      web.navigationDelegate = self
      readyPath = CommandLine.arguments[2]
      web.loadHTMLString("<p id='text'>Tero synthetic selection fixture</p>", baseURL: nil)
      view = web
    } else if scenario == "secure" {
      let field = NSSecureTextField(frame: NSRect(x: 20, y: 40, width: 350, height: 30))
      field.stringValue = "synthetic fixture only"
      view = field
    } else if scenario == "unsupported" {
      let button = NSButton(title: "Synthetic button", target: nil, action: nil)
      button.frame = NSRect(x: 20, y: 40, width: 250, height: 30)
      view = button
    } else {
      let text = SlowTextView(frame: NSRect(x: 20, y: 20, width: 380, height: 90))
      text.string = "Tero synthetic selection fixture"
      text.isEditable = !["slow-reading", "range-reading"].contains(scenario)
      text.rangeOnly = scenario == "range-reading"
      text.isSelectable = true
      text.transient = scenario == "transient"
      text.setSelectedRange(NSRange(location: 0, length: scenario == "empty" ? 0 : text.string.utf16.count))
      view = text
    }
    window.contentView?.addSubview(view)
    var focus = view
    if scenario == "split-focus" {
      // The document retains a visible selection while an empty composer owns focus.
      let composer = NSTextField(frame: NSRect(x: 20, y: 110, width: 350, height: 22))
      window.contentView?.addSubview(composer)
      focus = composer
    }
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(focus)
    if scenario == "web-reading" { return }
    // A marker lets the parent start capture after AppKit owns the focused view.
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(180))
      let state: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier,
                                "active": NSApp.isActive, "key": window.isKeyWindow]
      if let data = try? JSONSerialization.data(withJSONObject: state) {
        try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
      }
    }
  }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    webView.evaluateJavaScript("const r = document.createRange(); r.selectNodeContents(document.getElementById('text')); const s = window.getSelection(); s.removeAllRanges(); s.addRange(r);") { _, error in
      guard error == nil else { exit(1) }
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(250))
        guard let path = self.readyPath, let window = self.window else { exit(1) }
        let state: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier,
                                  "active": NSApp.isActive, "key": window.isKeyWindow]
        if let data = try? JSONSerialization.data(withJSONObject: state) {
          try? data.write(to: URL(fileURLWithPath: path))
        }
      }
    }
  }

}

@main struct FixtureMain {
  @MainActor static func main() {
    let app = NSApplication.shared
    let delegate = FixtureDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
  }
}
