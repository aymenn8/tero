import AppKit
import MapKit
import SwiftUI
import QuickLookUI
import ImageIO
import PDFKit

@MainActor final class SmokePlanningConnection: PlanningConnection {
  var saved: [ReviewedCommitment] = []
  var fails = false
  var accessGranted: Bool { !fails }
  var accessDenied: Bool { fails }
  func connect() async throws -> [PlanningContainer] {
    try await Task.sleep(for: .milliseconds(40))
    if fails { throw ApplePlanningConnection.Failure.denied }
    return [.init(id: "fixture", title: "Synthetic list")]
  }
  func create(_ items: [ReviewedCommitment], containerID: String) throws -> Int {
    precondition(containerID == "fixture")
    if fails { throw ApplePlanningConnection.Failure.save }
    saved += items; return items.count
  }
}

@MainActor final class SmokeUtilityServices: SelectionUtilityServices {
  var opened = false
  var directions = false
  var cancelled = false
  func rate(source: String, target: String) async throws -> CurrencyRate {
    try await Task.sleep(for: .milliseconds(80))
    return CurrencyRate(date: "2026-10-06", base: source, quote: target, rate: 1.2)
  }
  func places(query: String) async throws -> [MKMapItem] {
    try await Task.sleep(for: .milliseconds(80))
    return ["Paris", "London"].enumerated().map { index, name in
      let item = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: 48 + Double(index), longitude: 2)))
      item.name = name
      return item
    }
  }
  func open(_ item: MKMapItem, directions: Bool) -> Bool { opened = true; self.directions = directions; return true }
  func cancel() { cancelled = true }
}

@MainActor final class SmokeDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let controller = PanelController()
    Task { @MainActor in
      if CommandLine.arguments.contains("--icons-only") {
        for symbol in Set(Action.allCases.map(\.iconName) + HomeAction.allCases.map(\.iconName) + TextHabit.iconChoices.map(\.symbol)) {
          precondition(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "Missing symbol: \(symbol)")
        }
        for action in ActionCatalog.definitions.map(\.id) {
          let bubble = NSHostingView(rootView: ActionBubble(action: action, selected: false) {})
          precondition(bubble.fittingSize.width <= ActionBubble.width(title: action.title, leadingSymbol: action.iconName) + 1)
        }
        controller.presentSmokeStatus(.selected("A synthetic sentence for mode icons."))
        try? await Task.sleep(for: .milliseconds(500))
        controller.smokeSnapshot("mode-icons")
        controller.dismiss(restoreFocus: false)
        controller.smokeCapturedEmptyHome()
        try? await Task.sleep(for: .milliseconds(500))
        controller.smokeSnapshot("home-icons")
        controller.dismiss(restoreFocus: false)
        let editor = NSHostingView(rootView: TextHabitEditorView(store: .shared,
          habit: TextHabit(name: "Email summary", instruction: "Summarize this email.", iconName: "envelope")))
        let window = NSWindow(contentRect: NSRect(x: 250, y: 200, width: 520, height: 570), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = editor
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(400))
        if let bitmap = editor.bitmapImageRepForCachingDisplay(in: editor.bounds) {
          editor.cacheDisplay(in: editor.bounds, to: bitmap)
          try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/tero-icon-editor.png"))
        }
        window.close()
        print("PASS: mode symbols, bubble widths, home and custom editor rendering")
        NSApp.terminate(nil)
        return
      }
      if CommandLine.arguments.contains("--opening-only") {
        let host = NSWindow(contentRect: NSRect(x: 200, y: 250, width: 420, height: 160),
                            styleMask: [.titled], backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        let editor = NSTextField(frame: NSRect(x: 20, y: 60, width: 380, height: 30))
        editor.stringValue = "Synthetic source selection"
        host.contentView?.addSubview(editor)
        app.activate(ignoringOtherApps: true); host.makeKeyAndOrderFront(nil); host.makeFirstResponder(editor)
        try? await Task.sleep(for: .milliseconds(100))
        let field = editor.currentEditor() as! NSTextView
        field.setSelectedRange(NSRange(location: 0, length: 9))
        controller.smokeBeginOpening()
        try? await Task.sleep(for: .milliseconds(80))
        precondition(controller.invocationOpening && controller.smokeVisible && !controller.smokeOpeningIsKey)
        precondition(host.isKeyWindow && field.selectedRange() == NSRange(location: 0, length: 9))
        controller.smokeSnapshot("invocation-opening")
        try? await Task.sleep(for: .milliseconds(760))
        FileHandle.standardOutput.write(Data("Opening diagnostics: pending=\(controller.invocationOpening), visible=\(controller.smokeVisible), key=\(controller.smokeOpeningIsKey), provider=\(controller.rankingDiagnostic), modes=\(controller.state.suggestions.map(\.rawValue))\n".utf8))
        precondition(!controller.invocationOpening && controller.smokeVisible && controller.smokeOpeningIsKey)
        precondition(controller.state.suggestions == [.reply,.createEvent,.fix])
        controller.smokeSnapshot("invocation-opened")
        controller.dismiss(restoreFocus: false)
        host.makeKeyAndOrderFront(nil)
        controller.smokeBeginOpening()
        try? await Task.sleep(for: .milliseconds(60))
        precondition(controller.invocationOpening)
        controller.toggle() // The global shortcut cancels pending invocation work.
        try? await Task.sleep(for: .milliseconds(700))
        precondition(!controller.invocationOpening && !controller.smokeVisible && host.isKeyWindow)
        controller.smokeBeginOpening("offline")
        try? await Task.sleep(for: .milliseconds(350))
        precondition(!controller.invocationOpening && controller.smokeVisible)
        precondition(controller.rankingDiagnostic.hasPrefix("Local"))
        controller.dismiss(restoreFocus: false); host.close()
        print("PASS: opening stays non-key and preserves native source selection; ranked reveal, shortcut cancellation/no late reopen, and immediate local fallback. Synthetic provider.")
        app.terminate(nil); return
      }
      if CommandLine.arguments.contains("--clipboard-menu-only") {
        let root = try! LocalFileIO.workspace()
        let board = NSPasteboard.withUniqueName()
        let suite = "tero-clipboard-menu-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { board.releaseGlobally(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let store = ClipboardStore(url: root.appendingPathComponent("history.json"), defaults: defaults, pasteboard: board)
        board.clearContents(); board.setString("alpha   beta", forType: .string); store.poll()
        controller.clipboardStore = store
        controller.showHome(); controller.smokeIsolate(); controller.runHomeAction(.clipboard)
        try? await Task.sleep(for: .milliseconds(450))
        let frame = controller.smokeFrame
        controller.smokeRestoreWindowDelegate()
        controller.smokeNavigationKey(40, modifiers: .command)
        try? await Task.sleep(for: .milliseconds(350))
        precondition(controller.clipboardVisible && controller.clipboardPresented && controller.clipboardActionMenuPresented && !controller.clipboardClosing && controller.smokeFrame == frame)
        controller.smokeSnapshot("clipboard-inline-actions")
        controller.searchClipboardModes("Clean formatting")
        precondition(controller.clipboardModeStep.choices.map(\.id) == [Action.cleanFormatting.rawValue])
        controller.smokeNavigationKey(126)
        precondition(controller.clipboardModeSelectedID == nil)
        controller.smokeNavigationKey(53)
        try? await Task.sleep(for: .milliseconds(300))
        precondition(controller.clipboardVisible && !controller.clipboardActionMenuPresented && controller.smokeFrame == frame)
        controller.beginClipboardEntryActions()
        try? await Task.sleep(for: .milliseconds(200))
        controller.searchClipboardModes("Clean formatting")
        controller.smokeNavigationKey(36)
        try? await Task.sleep(for: .milliseconds(450))
        precondition(controller.explanationText == "alpha beta" && !controller.clipboardVisible && controller.smokePasteAttempts.isEmpty)
        controller.dismiss(restoreFocus: false)
        print("PASS: clipboard Actions keeps its window/frame, searchable shared choices, arrows/Escape/Enter, explicit mode dispatch without paste. Synthetic isolated clipboard.")
        app.terminate(nil); return
      }
      if CommandLine.arguments.contains("--clipboard-only") {
        let root = try! LocalFileIO.workspace()
        let board = NSPasteboard.withUniqueName()
        let suite = "tero-clipboard-ui-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { board.releaseGlobally(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let store = ClipboardStore(url: root.appendingPathComponent("history.json"), defaults: defaults, pasteboard: board)
        @MainActor func record(_ text: String) {
          store.browsing = false; board.clearContents(); board.setString(text, forType: .string); store.poll(); store.browsing = true
        }
        record("A pinned synthetic entry")
        controller.clipboardStore = store
        controller.showHome(); controller.smokeIsolate()
        controller.runHomeAction(.clipboard)
        precondition(controller.clipboardVisible && !controller.clipboardPresented)
        try? await Task.sleep(for: .milliseconds(500))
        precondition(controller.clipboardPresented && NSApp.keyWindow?.firstResponder is NSTextView)
        controller.smokeNavigationKey(35, modifiers: .command)
        let pinned = controller.selectedClipboardEntry!
        precondition(pinned.isPinned)
        let restored = ClipboardStore(url: root.appendingPathComponent("history.json"), defaults: defaults, pasteboard: board)
        precondition(restored.history.entries[0].isPinned)
        record("https://example.com/article?utm_source=fixture&id=42#details")
        controller.clipboardSelectedID = store.history.entries.first { $0.kind == .link }!.id
        precondition(controller.clipboardPrimaryTitle == "Copy")
        board.clearContents()
        controller.smokeReturnKey()
        precondition(board.string(forType: .string) == controller.selectedClipboardEntry?.text)
        precondition(controller.clipboardVisible)
        controller.copyClipboardLink(domain: false)
        precondition(board.string(forType: .string) == "https://example.com/article?id=42#details")
        controller.copyClipboardLink(domain: true)
        precondition(board.string(forType: .string) == "example.com")
        controller.clipboardQuery = "type:link article"
        precondition(controller.clipboardEntries.count == 1)
        controller.clipboardQuery = ""
        record("alpha   beta")
        controller.clipboardSelectedID = store.history.entries.first { $0.text == "alpha   beta" }!.id
        controller.smokeSnapshot("clipboard-actions")
        controller.smokeNavigationKey(40, modifiers: .command)
        try? await Task.sleep(for: .milliseconds(350))
        precondition(controller.clipboardActionMenuPresented && controller.clipboardVisible && !controller.clipboardClosing)
        controller.smokeNavigationKey(53)
        try? await Task.sleep(for: .milliseconds(300))
        precondition(controller.clipboardVisible && controller.selectedClipboardEntry?.text == "alpha   beta")
        controller.beginClipboardEntryActions()
        controller.searchClipboardModes("Clean formatting")
        controller.chooseClipboardMode(Action.cleanFormatting.rawValue)
        try? await Task.sleep(for: .milliseconds(450))
        precondition(controller.explanationText == "alpha beta" && controller.smokePasteAttempts.isEmpty)
        controller.dismiss(restoreFocus: false)
        controller.showHome(); controller.smokeIsolate(); controller.runHomeAction(.clipboard)
        try? await Task.sleep(for: .milliseconds(400))
        controller.clipboardSelectedID = store.history.entries.first { $0.text == "alpha   beta" }!.id
        controller.beginClipboardEntryActions()
        let sentinel = board.string(forType: .string)
        controller.chooseClipboardMode(Action.fix.rawValue)
        try? await Task.sleep(for: .milliseconds(350))
        for _ in 0..<100 where controller.readingInProgress { try? await Task.sleep(for: .milliseconds(20)) }
        precondition(controller.explanationText == "Corrected" && controller.smokePasteAttempts.isEmpty && board.string(forType: .string) == sentinel)
        controller.dismiss(restoreFocus: false)
        let file = root.appendingPathComponent("old-copy.txt")
        try! Data("A historical copied file".utf8).write(to: file)
        store.browsing = false; board.clearContents(); board.writeObjects([file as NSURL]); store.poll()
        controller.showHome(); controller.smokeIsolate(); controller.runHomeAction(.clipboard)
        try? await Task.sleep(for: .milliseconds(400))
        controller.clipboardSelectedID = store.history.entries.first { $0.kind == .files }!.id
        controller.beginClipboardEntryActions()
        controller.chooseClipboardMode(Action.renameFile.rawValue)
        try? await Task.sleep(for: .milliseconds(350))
        precondition(controller.fileContext?.fileOrigin == .clipboardFiles(controller.clipboardActionEntryID!))
        precondition(controller.fileWorkflow?.kind == .rename)
        controller.dismiss(restoreFocus: false)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.bitmapData?.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        let png = bitmap.representation(using: .png, properties: [:])!
        store.browsing = false; board.clearContents(); board.setData(png, forType: .png); store.poll()
        controller.showHome(); controller.smokeIsolate(); controller.runHomeAction(.clipboard)
        try? await Task.sleep(for: .milliseconds(400))
        controller.clipboardSelectedID = store.history.entries.first { $0.kind == .image }!.id
        controller.beginClipboardEntryActions()
        try? await Task.sleep(for: .milliseconds(350))
        let imageContext = controller.smokeClipboardPreparedContext!
        let actions = ActionCatalog.definitions.filter { $0.accepts(.init(fileContext: imageContext)) }.map(\.id)
        precondition(actions.contains(.summarizeFile) && !actions.contains(.renameFile))
        let imageURL = imageContext.files[0].url
        controller.chooseClipboardMode(Action.summarizeFile.rawValue)
        try? await Task.sleep(for: .milliseconds(350))
        for _ in 0..<100 where controller.readingInProgress { try? await Task.sleep(for: .milliseconds(20)) }
        precondition(controller.explanationText?.contains("Complete fixture") == true)
        controller.dismiss(restoreFocus: false)
        precondition(!FileManager.default.fileExists(atPath: imageURL.path))
        controller.showHome(); controller.smokeIsolate(); controller.runHomeAction(.clipboard)
        controller.backFromClipboard()
        controller.dismiss(restoreFocus: false)
        controller.showHome(); controller.runHomeAction(.clipboard)
        try? await Task.sleep(for: .milliseconds(450))
        precondition(controller.clipboardVisible && controller.clipboardPresented && !controller.clipboardClosing)
        controller.closeClipboardWindow()
        precondition(controller.clipboardVisible && controller.clipboardClosing)
        try? await Task.sleep(for: .milliseconds(350))
        precondition(!controller.smokeVisible && !controller.clipboardVisible && !store.browsing)
        print("PASS: clipboard transition/cancellation, pin persistence, search, clean link/domain, text modes without paste, genuine historical file execution and temporary image reading cleanup. Isolated pasteboard and synthetic files; AI mocked.")
        app.terminate(nil); return
      }
      if CommandLine.arguments.contains("--files-only") {
        let folder = try! LocalFileIO.workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("first.txt"), second = folder.appendingPathComponent("second.txt")
        try! Data("Project Orion invoice".utf8).write(to: first)
        try! Data("Second fixture".utf8).write(to: second)
        @MainActor func open(_ urls: [URL], _ action: Action) {
          var context = InvocationContext(capturedAt: .now, applicationID: "com.apple.finder")
          context.files = urls.map { InvocationContext.FileObservation.read($0) }
          controller.smokeFileSelection(context)
          controller.beginActionSearch(query: action.title)
          controller.choose(action)
        }
        open([first, second], .batchRename)
        try? await Task.sleep(for: .milliseconds(250))
        let rename = controller.fileWorkflow!
        precondition(rename.kind == .batchRename && rename.canRun)
        rename.names = ["projectOne", "projectTwo"]
        precondition(rename.targets.map(\.lastPathComponent) == ["projectOne.txt", "projectTwo.txt"])
        try? await Task.sleep(for: .milliseconds(400))
        controller.smokeSnapshot("file-rename-preview")
        let frame = controller.smokeFrame!
        controller.smokeReturnKey()
        precondition(rename.busy && controller.smokeFrame == frame)
        for _ in 0..<100 where !rename.succeeded && rename.message == nil { try? await Task.sleep(for: .milliseconds(20)) }
        precondition(rename.succeeded && rename.outputs.count == 2)
        try? await Task.sleep(for: .milliseconds(1000))
        precondition(!controller.smokeVisible)
        let renamed = rename.outputs
        open(renamed, .moveFiles)
        let move = controller.fileWorkflow!
        precondition(!move.canRun)
        let destination = folder.appendingPathComponent("destination")
        try! FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        move.destination = destination
        move.selectedID = "run"
        controller.updateFileWorkflowPresentation()
        try? await Task.sleep(for: .milliseconds(250))
        controller.smokeSnapshot("file-move-preview")
        controller.smokeReturnKey()
        for _ in 0..<100 where !move.succeeded && move.message == nil { try? await Task.sleep(for: .milliseconds(20)) }
        precondition(move.succeeded && move.outputs.count == 2)
        try? await Task.sleep(for: .milliseconds(1000))
        open([move.outputs[0]], .renameFile)
        try? await Task.sleep(for: .milliseconds(300))
        precondition(controller.fileWorkflow!.names == ["orionInvoice"])
        controller.smokeNavigationKey(53)
        precondition(controller.fileWorkflow == nil && controller.smokeVisible)
        controller.dismiss(restoreFocus: false)
        // This is test-only preference cleanup; no real folder is remembered.
        let current = UserDefaults.standard.stringArray(forKey: "tero.recentMoveFolders") ?? []
        UserDefaults.standard.set(current.filter { $0 != destination.path }, forKey: "tero.recentMoveFolders")
        print("PASS: file review, Enter, content name suggestion, batch rename, move, stable loading and success close; temporary files only, Finder revalidation simulated")
        NSApp.terminate(nil); return
      }
      if CommandLine.arguments.contains("--brand-only") {
        controller.showHome(); controller.smokeIsolate()
        try? await Task.sleep(for:.milliseconds(500))
        controller.smokeSnapshot("brand-home")
        precondition(controller.smokeFrame!.width==480)
        controller.runHomeAction(.ask)
        try? await Task.sleep(for:.milliseconds(600))
        precondition(controller.smokeFrame!.height==controller.askEditorHeight+AskInputView.verticalChrome+2*PanelPlacement.contentInset)
        controller.smokeSnapshot("brand-ask")
        controller.dismiss(restoreFocus:false)
        controller.smokeUtility(.convertUnits,"12 km")
        try? await Task.sleep(for:.milliseconds(250))
        controller.smokeSnapshot("brand-choices")
        controller.modeChoices?.activate("mi")
        try? await Task.sleep(for:.milliseconds(600))
        precondition(controller.explanationText?.contains("7.456")==true)
        controller.smokeSnapshot("brand-result")
        controller.dismiss(restoreFocus:false)
        let draft=CommitmentDraft(kind:.event,title:"Project review",owner:nil,deadline:nil,condition:nil,evidence:"Project review tomorrow at 15:00",date:"2026-10-07",time:"15:00",endDate:"2026-10-07",endTime:"15:30")
        controller.presentSmokeStatus(.selected("Synthetic calendar fixture"))
        controller.smokeReviewSession(CommitmentSession([draft],destination:.calendar,connection:SmokePlanningConnection()))
        try? await Task.sleep(for:.milliseconds(600))
        controller.smokeSnapshot("brand-calendar")
        controller.dismiss(restoreFocus:false)
        print("PASS: branded home/choices, compact Ask header sizing, shared result and Calendar headers. Synthetic data; no clipboard or calendar writes.")
        app.terminate(nil);return
      }
      if CommandLine.arguments.contains("--utilities-only") {
        var result = ""
        let services = SmokeUtilityServices()
        let money = SelectionUtilitySession(action: .convertCurrencies, text: "$100", result: { result = $0 }, back: {}, opened: {}, services: services)
        precondition(money.options.map(\.id).prefix(3) == ["USD","CAD","AUD"])
        money.presentation.activate("USD")
        money.presentation.activate("EUR")
        try? await Task.sleep(for: .milliseconds(130))
        precondition(result.contains("120 EUR") && result.contains("Frankfurter · 2026-10-06"))
        let maps = SelectionUtilitySession(action: .directions, text: "10 Downing Street, London", result: { _ in }, back: {}, opened: {}, services: services)
        try? await Task.sleep(for: .milliseconds(130))
        precondition(!services.opened && maps.options.count == 2)
        maps.presentation.activate("1")
        precondition(services.opened && services.directions)
        services.opened = false
        let pending = SelectionUtilitySession(action: .openMaps, text: "Paris", result: { _ in }, back: {}, opened: {}, services: services)
        pending.cancel(); try? await Task.sleep(for: .milliseconds(130))
        precondition(!services.opened && services.cancelled)
        controller.smokeUtility(.convertUnits, "12 km")
        try? await Task.sleep(for: .milliseconds(160))
        precondition(controller.utilitySession != nil && controller.modeChoices != nil)
        controller.smokeNavigationKey(123)
        precondition(controller.modeChoices?.step.selectedID == nil)
        controller.smokeNavigationKey(124); controller.smokeNavigationKey(36)
        try? await Task.sleep(for: .milliseconds(600))
        precondition(controller.explanationText?.contains("7.456") == true && controller.smokePasteAttempts.isEmpty)
        controller.smokeSnapshot("utility-result")
        controller.dismiss()
        controller.smokeUtility(.convertTimeZones, "2026-10-08 3 PM EST")
        try? await Task.sleep(for: .milliseconds(600))
        precondition(controller.utilitySession == nil && controller.modeChoices == nil)
        precondition(controller.explanationText?.contains("08 Oct 2026") == true)
        precondition(controller.smokeFrame!.height > 100)
        controller.smokeSnapshot("utility-explicit-time")
        controller.dismiss()
        controller.smokeUtility(.convertCurrencies, "100 EUR")
        controller.modeChoices?.activate("USD")
        try? await Task.sleep(for: .milliseconds(600))
        precondition(controller.utilitySession == nil && controller.modeChoices == nil)
        precondition(controller.explanationText?.contains("120 USD") == true)
        precondition(controller.smokeFrame!.height > 100)
        controller.smokeSnapshot("utility-currency")
        controller.dismiss()
        controller.smokeUtility(.convertCurrencies,"100 EUR")
        controller.modeChoices?.search?("dhs")
        try? await Task.sleep(for:.milliseconds(180))
        precondition(controller.modeChoices?.step.choices.map(\.id)==["MAD"])
        controller.smokeSnapshot("utility-currency-search")
        controller.smokeNavigationKey(36)
        try? await Task.sleep(for:.milliseconds(600))
        precondition(controller.explanationText?.contains("120 MAD")==true)
        controller.dismiss()
        controller.smokeUtility(.translate,"Synthetic selection")
        controller.modeChoices?.search?("span")
        precondition(controller.modeChoices?.step.choices.map(\.id)==["es"])
        controller.smokeNavigationKey(53)
        precondition(controller.modeChoices?.searchQuery=="")
        controller.smokeNavigationKey(53)
        precondition(controller.modeChoices==nil)
        controller.dismiss()
        controller.smokeUtility(.convertTimeZones, "3 PM EST")
        try? await Task.sleep(for: .milliseconds(100))
        controller.modeChoices?.activate("date")
        try? await Task.sleep(for: .milliseconds(180))
        precondition(controller.utilitySession?.choosingDate == true)
        controller.smokeSnapshot("utility-date")
        controller.smokeNavigationKey(53)
        precondition(controller.utilitySession?.choosingDate == false)
        controller.smokeNavigationKey(53)
        precondition(controller.utilitySession == nil && controller.state.executing == nil)
        print("PASS: shared utility choices, keyboard Back, local result/no paste, custom date, currency rates, ambiguous destinations and cancellation. Synthetic providers only.")
        controller.dismiss(); app.terminate(nil); return
      }
      if CommandLine.arguments.contains("--unified-ask-only") {
        @MainActor func ask(_ question: String) {
          controller.showHome()
          controller.runHomeAction(.ask)
          controller.smokeIsolate()
          controller.updateAskQuery(question)
          controller.submitAsk()
          precondition(controller.askRouting)
        }
        precondition(controller.homeActions == [.ask, .clipboard, .createHabit])
        ask("Product request")
        try? await Task.sleep(for: .milliseconds(600))
        precondition(controller.shoppingSession?.result?.products.count == 1)
        precondition(!controller.askVisible && !controller.askRouting)
        controller.smokeSnapshot("unified-ask-products")
        controller.dismiss()
        ask("Ordinary question")
        try? await Task.sleep(for: .milliseconds(1300))
        precondition(controller.shoppingSession == nil && controller.explanationText?.contains("Complete fixture") == true)
        controller.dismiss()
        ask("Offline question")
        try? await Task.sleep(for: .milliseconds(1300))
        precondition(controller.shoppingSession == nil && controller.explanationText?.contains("Complete fixture") == true)
        controller.dismiss()
        ask("Product request")
        controller.dismiss()
        controller.showHome()
        try? await Task.sleep(for: .milliseconds(600))
        precondition(controller.homeVisible && controller.shoppingSession == nil && controller.explanationText == nil)
        controller.runHomeAction(.ask)
        controller.smokeIsolate()
        controller.updateAskQuery("Product request")
        controller.submitAsk()
        controller.updateAskQuery("Changed question")
        try? await Task.sleep(for: .milliseconds(600))
        precondition(controller.askVisible && !controller.askRouting && controller.shoppingSession == nil)
        precondition(controller.smokePasteAttempts.isEmpty)
        print("PASS: unified Ask home, Jev product cards, ordinary answer, offline fallback, cancellation and edited-request guards. Synthetic providers only.")
        controller.dismiss(); app.terminate(nil); return
      }
      if CommandLine.arguments.contains("--result-refinement-only") {
        controller.presentSmokeStatus(.selected("Synthetic message"))
        let before = "A prepared answer that stays visible while you describe your changes."
        controller.smokeReadingResult(before)
        try? await Task.sleep(for: .milliseconds(250))
        let height = controller.smokeFrame!.height
        controller.smokeNavigationKey(15, modifiers: .command)
        try? await Task.sleep(for: .milliseconds(200))
        precondition(controller.askVisible && controller.refiningResult && controller.explanationText == before)
        precondition(controller.smokeFrame!.height > height)
        precondition(NSApp.keyWindow?.firstResponder is NSTextView)
        controller.smokeSnapshot("inline-result-refinement")
        controller.updateAskQuery("Make it clearer")
        controller.smokeNavigationKey(53)
        precondition(!controller.askVisible && controller.explanationText == before)
        controller.beginResultRefinement()
        controller.updateAskQuery("Make it clearer")
        controller.smokeReturnKey()
        precondition(controller.explanationText == before && controller.readingInProgress)
        try? await Task.sleep(for: .milliseconds(1100))
        precondition(controller.explanationText == "Revised: Make it clearer" && !controller.readingInProgress && controller.readingError == nil)
        controller.smokeSnapshot("inline-result-updated")
        controller.beginResultRefinement()
        controller.updateAskQuery("Cancelled change")
        controller.submitAsk()
        controller.restoreResult()
        try? await Task.sleep(for: .milliseconds(1100))
        precondition(controller.explanationText == "Revised: Make it clearer")
        precondition(controller.smokePasteAttempts.isEmpty)
        print("PASS: inline answer stays visible, field grows card/focus, Escape restores, Return replaces answer, cancellation rejects late output; simulated provider only")
        controller.dismiss(); app.terminate(nil); return
      }
      if CommandLine.arguments.contains("--text-messages-only") {
        @MainActor func open(_ action: Action, editable: Bool = false, text: String = "Synthetic message") {
          controller.dismiss(restoreFocus: false)
          controller.smokePasteAttempts.removeAll()
          controller.presentSmokeStatus(.selected(text))
          if editable { controller.smokeMakeSelectionEditable() }
          controller.beginActionSearch(query: action.title)
          controller.smokeReturnKey()
          precondition(controller.state.executing == action)
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("text message sentinel", forType: .string)
        for action in [Action.rewrite, .tone, .changeCase] {
          open(action)
          precondition(controller.choosingTextOptions && controller.modeChoices?.step.choices.count == 3)
          controller.smokeNavigationKey(123)
          precondition(controller.modeChoices?.step.selectedID == nil)
          controller.smokeReturnKey()
          precondition(controller.state.executing == nil && controller.state.isSearching)
          precondition(controller.state.searchQuery == action.title)
        }
        for action in [Action.rewrite, .tone, .simplify, .fix, .keyPoints] {
          for editable in [false, true] {
            open(action, editable: editable)
            if controller.choosingTextOptions { controller.smokeReturnKey() }
            try? await Task.sleep(for: .milliseconds(1100))
            if editable {
              precondition(controller.explanationText == nil && controller.smokePasteAttempts.count == 1)
            } else {
              precondition(controller.explanationText?.isEmpty == false && controller.smokePasteAttempts.isEmpty)
              precondition(NSPasteboard.general.string(forType: .string) == "text message sentinel")
            }
          }
        }
        open(.cleanFormatting, text: "Hello  \n\n\nWorld\t")
        precondition(controller.explanationText == "Hello\n\nWorld")
        open(.changeCase, text: "Hello")
        controller.modeChoices?.activate("uppercase")
        precondition(controller.explanationText == "HELLO")
        try? await Task.sleep(for: .milliseconds(250))
        controller.smokeSnapshot("text-case-result")
        open(.changeCase, editable: true, text: "Hello")
        controller.modeChoices?.activate("lowercase")
        try? await Task.sleep(for: .milliseconds(400))
        precondition(controller.smokePasteAttempts == ["hello"])
        open(.translate)
        let firstPage = controller.modeChoices!.step.choices
        precondition(firstPage.count == 4)
        controller.modeChoices?.activate("more-languages")
        precondition(controller.modeChoices!.step.choices.first?.id != firstPage.first?.id)
        controller.smokeNavigationKey(53)
        precondition(controller.state.executing == nil)
        open(.simplify)
        try? await Task.sleep(for: .milliseconds(1000))
        let before = controller.explanationText!
        controller.smokeNavigationKey(15, modifiers: .command)
        precondition(controller.askVisible && controller.refiningResult)
        precondition(controller.explanationText == before, "Keep the result visible above the refinement field")
        controller.smokeSnapshot("inline-result-refinement")
        controller.updateAskQuery("Make it clearer")
        controller.smokeNavigationKey(53)
        precondition(!controller.askVisible && controller.explanationText == before)
        controller.smokeNavigationKey(15, modifiers: .command)
        controller.updateAskQuery("Make it clearer")
        controller.submitAsk()
        precondition(controller.explanationText == before, "Keep the existing result until the new output arrives")
        try? await Task.sleep(for: .milliseconds(1000))
        precondition(controller.explanationText == "Revised: Make it clearer")
        precondition(controller.smokePasteAttempts.isEmpty)
        precondition(NSPasteboard.general.string(forType: .string) == "text message sentinel")
        controller.smokeNavigationKey(15, modifiers: .command)
        controller.updateAskQuery("Cancelled change")
        controller.submitAsk()
        controller.dismiss(restoreFocus: false)
        controller.presentSmokeStatus(.selected("New invocation"))
        try? await Task.sleep(for: .milliseconds(900))
        precondition(controller.explanationText == nil && controller.smokeVisible)
        controller.dismiss(restoreFocus: false)
        print("PASS: text modes, shared choices/Back, native case/clean, editable dispatch, read-only clipboard preservation, language pages, result refinement/back and cancellation")
        NSApp.terminate(nil); return
      }
      if CommandLine.arguments.contains("--reinvoke-only") {
        controller.presentSmokeStatus(.selected("Synthetic selection"))
        controller.smokeOldSource(); controller.smokeMakeKey()
        controller.toggle()
        precondition(!controller.smokeVisible && controller.smokeRecaptures == 0, "Shortcut still closes the active panel")
        controller.presentSmokeStatus(.selected("Synthetic selection")); controller.smokeOldSource()
        controller.smokeFrontPID = 123456
        controller.toggle()
        precondition(!controller.smokeVisible && controller.smokeRecaptures == 1, "Changed source app needs a fresh capture in one invocation")
        precondition(controller.selection == nil && controller.state.executing == nil)
        controller.presentSmokeStatus(.selected("Synthetic selection")); controller.smokeOldSource()
        controller.smokeFrontPID = ProcessInfo.processInfo.processIdentifier
        controller.smokeReleaseKey()
        // The application's own foreground state must not trigger reading itself.
        controller.toggle()
        precondition(controller.smokeRecaptures == 1)
        print("PASS: active-panel toggle, fresh capture after switching app, cleared old selection and no self capture; no real app reads")
        NSApp.terminate(nil); return
      }
      if CommandLine.arguments.contains("--commitments-only") {
        let draft = CommitmentDraft(kind: .task, title: "Call", owner: nil, deadline: "tomorrow", condition: "if approved", evidence: "Call tomorrow if approved.", date: "2026-10-07", time: nil, endDate: nil, endTime: nil)
        let fake = SmokePlanningConnection()
        let session = CommitmentSession([draft], destination: .reminders, connection: fake)
        let card = NSHostingView(rootView: CommitmentContextCard(row: .constant(session.rows[0]),
          destination: .reminders, expanded: false, toggleEditing: {}).frame(width: 352).fixedSize(horizontal: false, vertical: true))
        precondition(card.fittingSize.height <= session.reviewHeight + 2, "Context card must fit its adaptive review height")
        precondition(!session.canCreate); session.create(); precondition(fake.saved.isEmpty)
        await session.connect(); precondition(session.canCreate)
        session.rows[0].selected = false; precondition(!session.canCreate)
        session.rows[0].selected = true; session.rows[0].title = ""; precondition(!session.canCreate)
        session.rows[0].title = "Edited call"; session.create(); session.create()
        precondition(fake.saved.count == 1 && session.created)
        precondition(fake.saved[0].start?.hour == nil && fake.saved[0].notes.contains("if approved"))
        let cancelled = CommitmentSession([draft], destination: .reminders, connection: fake)
        let pending = Task { await cancelled.connect() }; cancelled.cancel(); await pending.value
        precondition(cancelled.containers.isEmpty && !cancelled.canCreate)
        let denied = SmokePlanningConnection(); denied.fails = true
        let deniedSession = CommitmentSession([draft], destination: .reminders, connection: denied)
        precondition(deniedSession.needsSettings, "Denied access opens settings immediately, without a redundant request")
        await deniedSession.connect(); precondition(!deniedSession.canCreate && deniedSession.needsSettings)
        precondition(deniedSession.settingsURL.absoluteString.hasSuffix("Privacy_Reminders"))
        deniedSession.beganSettingsVisit(); await deniedSession.refreshAfterSettings()
        precondition(deniedSession.needsSettings && deniedSession.waitingForSettings)
        denied.fails = false; await deniedSession.refreshAfterSettings()
        precondition(deniedSession.canCreate && !deniedSession.needsSettings && !deniedSession.waitingForSettings && denied.saved.isEmpty)
        let failed = SmokePlanningConnection()
        let failedSession = CommitmentSession([draft], destination: .reminders, connection: failed)
        await failedSession.connect(); failed.fails = true; failedSession.create()
        precondition(failedSession.uncertain && !failedSession.canCreate)
        var event = draft; event.kind = .event
        let calendar = CommitmentSession([event], destination: .calendar, connection: fake)
        await calendar.connect(); precondition(!calendar.canCreate, "Missing event time/end cannot silently save")
        calendar.rows[0].hasDate = true; calendar.rows[0].hasEnd = true
        precondition(calendar.canCreate)
        var ambiguous = draft; ambiguous.date = nil; ambiguous.scheduleIssue = "ambiguous_date"
        let review = CommitmentSession([ambiguous], destination: .reminders, connection: fake)
        await review.connect(); precondition(!review.canCreate)
        review.rows[0].scheduleConfirmed = true; precondition(review.canCreate)
        var zoneEvent = event; zoneEvent.timeZone = "Etc/GMT+5"; zoneEvent.time = "15:00"; zoneEvent.endDate = zoneEvent.date; zoneEvent.endTime = "16:30"
        let zoned = CommitmentSession([zoneEvent], destination: .calendar, connection: fake)
        await zoned.connect(); precondition(zoned.canCreate)
        precondition(zoned.rows[0].reviewed().start?.timeZone?.identifier == "Etc/GMT+5")
        zoned.rows[0].chooseZone("Europe/Paris")
        precondition(zoned.rows[0].zone.identifier == "Europe/Paris" && zoned.rows[0].reviewed().start?.hour == 15)
        zoned.rows[0].allDay = true
        precondition(zoned.rows[0].reviewed().allDay && zoned.rows[0].reviewed().start?.hour == nil)
        let expandedCard = NSHostingView(rootView: CommitmentContextCard(row: .constant(review.rows[0]), destination: .reminders, expanded: true, toggleEditing: {}).frame(width: 352).fixedSize(horizontal: false, vertical: true))
        precondition(expandedCard.fittingSize.height <= review.reviewHeight + 2, "Expanded ambiguity card must fit")
        for action in [Action.createTasks, .createEvent] {
          controller.presentSmokeStatus(.selected("Call tomorrow."))
          controller.smokeMakeSelectionEditable()
          controller.beginActionSearch(query: action == .createTasks ? "create tasks" : "calendar")
          controller.choose(action)
          precondition(controller.state.executing == action && controller.commitmentSession == nil)
          try? await Task.sleep(for: .milliseconds(450))
          controller.smokeSnapshot(action == .createTasks ? "task-loading" : "calendar-loading")
          try? await Task.sleep(for: .milliseconds(850))
          precondition(controller.commitmentSession?.rows.count == 1 && controller.smokePasteAttempts.isEmpty, "Plan state: rows=\(String(describing: controller.commitmentSession?.rows.count)), error=\(String(describing: controller.smokeCommitmentError)), visible=\(controller.smokeVisible)")
          precondition(controller.explanationText == nil)
          controller.smokeSnapshot(action == .createTasks ? "task-review" : "calendar-review")
          if let preview = controller.commitmentSession {
            preview.editingRowID = preview.rows[0].id; controller.updateCommitmentPresentation()
            controller.smokeSnapshot(action == .createTasks ? "task-editor" : "calendar-editor")
            await preview.connect(); controller.smokeSnapshot(action == .createTasks ? "task-connected" : "calendar-connected")
            let deniedAdapter = SmokePlanningConnection(); deniedAdapter.fails = true
            let accessPreview = CommitmentSession(preview.rows.map(\.draft), destination: preview.destination, connection: deniedAdapter)
            await accessPreview.connect(); controller.smokeReviewSession(accessPreview)
            controller.smokeSnapshot(action == .createTasks ? "task-permission" : "calendar-permission")
            accessPreview.beganSettingsVisit()
            controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))
            precondition(controller.smokeVisible && controller.commitmentSession === accessPreview)
            deniedAdapter.fails = false; await accessPreview.refreshAfterSettings()
            precondition(accessPreview.canCreate && deniedAdapter.saved.isEmpty)
          }
          controller.smokeNavigationKey(53)
          precondition(!controller.smokeVisible && controller.commitmentSession == nil)
        }
        controller.presentSmokeStatus(.selected("Call tomorrow.")); controller.beginActionSearch(query: "create tasks"); controller.choose(.createTasks)
        controller.dismiss(restoreFocus: false)
        controller.presentSmokeStatus(.selected("No pending work.")); controller.beginActionSearch(query: "create tasks"); controller.choose(.createTasks)
        try? await Task.sleep(for: .milliseconds(850))
        precondition(controller.commitmentSession?.rows.isEmpty == true && controller.smokePasteAttempts.isEmpty)
        controller.dismiss(restoreFocus: false)
        print("PASS: native commitment review, tasks/events routing, editable never pastes, dates, destination validation, create once, permission failure, uncertainty, cancellation and empty states. Fake Apple adapter only.")
        NSApp.terminate(nil); return
      }
      if CommandLine.arguments.contains("--file-summary-only") {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("tero-summary-smoke-" + UUID().uuidString)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let pdf = folder.appendingPathComponent("fixture.pdf")
        var box = CGRect(x: 0, y: 0, width: 400, height: 300)
        let writer = CGContext(pdf as CFURL, mediaBox: &box, nil)!
        writer.beginPDFPage(nil); writer.endPDFPage(); writer.closePDF()
        var context = InvocationContext(capturedAt: .now, applicationID: "com.apple.finder")
        context.files = [.read(pdf)]
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("Summary clipboard sentinel", forType: .string)
        controller.smokeFileSelection(context)
        precondition(controller.state.actions.contains(.summarizeFile))
        controller.choose(.summarizeFile)
        precondition(controller.fileContext == nil && controller.readingInProgress)
        try? await Task.sleep(for: .milliseconds(400))
        precondition(controller.explanationText == "Partial fixture" && controller.readingInProgress)
        try? await Task.sleep(for: .milliseconds(550))
        precondition(!controller.readingInProgress && controller.readingError == nil)
        precondition(controller.explanationText?.contains("Complete fixture") == true)
        precondition(controller.smokePasteAttempts.isEmpty)
        precondition(NSPasteboard.general.string(forType: .string) == "Summary clipboard sentinel")
        controller.smokeReturnKey()
        precondition(controller.smokePasteAttempts.isEmpty)
        controller.smokeSnapshot("file-summary-reading")
        controller.copyExplanation()
        precondition(NSPasteboard.general.string(forType: .string)?.contains("Complete fixture") == true)
        controller.dismiss()
        controller.smokeFileSelection(context)
        controller.smokeReturnKey()
        controller.dismiss()
        try? await Task.sleep(for: .milliseconds(900))
        precondition(!controller.smokeVisible && controller.explanationText == nil)
        print("PASS: PDF Summarize recommendation, progressive shared reading card, explicit copy, never paste and cancellation; Finder/provider simulated")
        NSApp.terminate(nil)
        return
      }
      if CommandLine.arguments.contains("--translation-options-only") {
        controller.presentSmokeStatus(.selected("Synthetic translation fixture"))
        controller.choose(.translate)
        precondition(controller.choosingTranslationLanguage, "Local options must open immediately")
        precondition(!controller.readingInProgress && controller.smokePasteAttempts.isEmpty)
        for _ in 0..<ResponseLanguage.allCases.count {
          if controller.translationBackSelected { break }
          controller.smokeNavigationKey(123)
        }
        precondition(controller.translationBackSelected, "Left arrow must reach Back")
        try? await Task.sleep(for: .milliseconds(150))
        controller.smokeSnapshot("translation-back-selected")
        controller.smokeReturnKey()
        precondition(!controller.choosingTranslationLanguage && controller.state.executing == nil)
        controller.beginActionSearch(query: "translate")
        controller.smokeReturnKey()
        precondition(controller.choosingTranslationLanguage)
        for _ in 0..<ResponseLanguage.allCases.count {
          if controller.translationBackSelected { break }
          controller.smokeNavigationKey(126)
        }
        precondition(controller.translationBackSelected)
        controller.smokeNavigationKey(124)
        precondition(!controller.translationBackSelected && controller.translationTarget == ResponseLanguage.translationChoices()[0],
          "Arrow must select the first visible language: \(String(describing:controller.modeChoices?.step))")
        controller.smokeNavigationKey(48)
        precondition(controller.translationTarget == ResponseLanguage.translationChoices()[1])
        controller.smokeNavigationKey(125)
        controller.smokeNavigationKey(125)
        controller.smokeNavigationKey(125)
        precondition(controller.translationBackSelected)
        controller.smokeNavigationKey(48, modifiers: .shift)
        precondition(!controller.translationBackSelected && controller.modeChoices?.step.selectedID == "more-languages")
        controller.smokeNavigationKey(53)
        precondition(controller.state.isSearching && controller.state.searchQuery == "translate")
        precondition(controller.smokePasteAttempts.isEmpty)
        controller.dismiss(restoreFocus: false)
        print("PASS: immediate Translate options, arrows/Tab include Back, Return and Escape restore originating search, no AI or paste")
        NSApp.terminate(nil)
        return
      }
      if CommandLine.arguments.contains("--ask-refine-only") {
        // Establish a real active source window for the nonactivating panel fixture.
        let source = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 200, height: 100),
          styleMask: [.titled], backing: .buffered, defer: false)
        source.isReleasedWhenClosed = false
        source.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        try? await Task.sleep(for: .milliseconds(150))
        controller.smokeCapturedEmptyHome(); controller.runHomeAction(.ask)
        try? await Task.sleep(for: .milliseconds(200))
        controller.smokeSnapshot("ask-opening-horizontal")
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else {
          preconditionFailure("Multiline Ask must focus: key=\(String(describing: NSApp.keyWindow)), responder=\(String(describing: NSApp.keyWindow?.firstResponder)), visible=\(controller.smokeVisible), ask=\(controller.askVisible)")
        }
        let frame = controller.smokeFrame
        precondition(controller.askEditorHeight == 22, "Empty Ask must start compact")
        editor.insertText("Rough fixture", replacementRange: NSRange(location: 0, length: 0))
        precondition(controller.askQuery == "Rough fixture")
        precondition(!controller.smokeNavigationKey(36, modifiers: .shift))
        editor.insertNewline(nil)
        controller.smokeType("Second line")
        let original = controller.askQuery
        precondition(original == "Rough fixture\nSecond line")
        precondition(controller.askEditorHeight > 22 && controller.smokeFrame!.height > frame!.height)
        let multilineFrame = controller.smokeFrame
        precondition(controller.smokeNavigationKey(15, modifiers: .command))
        precondition(controller.askRefining)
        controller.submitAsk()
        precondition(controller.askVisible && !controller.readingInProgress)
        try? await Task.sleep(for: .milliseconds(150))
        controller.smokeSnapshot("ask-refining")
        try? await Task.sleep(for: .milliseconds(500))
        precondition(!controller.askRefining && controller.askRefineError == nil)
        precondition(controller.askQuery == "Refined: " + original)
        precondition(editor.string == controller.askQuery)
        precondition(controller.smokeFrame == multilineFrame && NSApp.keyWindow?.firstResponder === editor)
        controller.smokeSnapshot("ask-refined")
        precondition(controller.smokeNavigationKey(6, modifiers: .command))
        try? await Task.sleep(for: .milliseconds(100))
        precondition(controller.askQuery == original && editor.string == original,
          "Cmd-Z must restore the original prompt: editor=\(editor.string), state=\(controller.askQuery)")
        controller.refineAskPrompt()
        controller.smokeType(" edited")
        let edited = controller.askQuery
        try? await Task.sleep(for: .milliseconds(600))
        precondition(!controller.askRefining && controller.askQuery == edited)
        controller.updateAskQuery("Error fixture")
        controller.refineAskPrompt()
        try? await Task.sleep(for: .milliseconds(600))
        precondition(controller.askRefineError != nil && controller.askQuery == "Error fixture")
        controller.updateAskQuery("Close fixture"); controller.refineAskPrompt()
        controller.backFromAsk(); controller.runHomeAction(.ask)
        try? await Task.sleep(for: .milliseconds(600))
        precondition(controller.askVisible && controller.askQuery.isEmpty && !controller.askRefining)
        // Long drafts grow to the cap, then scroll internally.
        controller.updateAskQuery(String(repeating: "A long multiline question. ", count: 80))
        try? await Task.sleep(for: .seconds(3))
        precondition(controller.askEditorHeight == 110 && controller.smokeVisible)
        let cappedFrame = controller.smokeFrame
        controller.updateAskQuery(controller.askQuery + String(repeating: " More text.", count: 80))
        precondition(controller.smokeFrame == cappedFrame)
        controller.smokeSnapshot("ask-long-prompt")
        controller.updateAskQuery("Send fixture")
        precondition(controller.askEditorHeight == 22 && controller.smokeFrame!.size == frame!.size)
        precondition(NSApp.keyWindow?.firstResponder is NSTextView)
        controller.smokeSnapshot("ask-compact-prompt")
        controller.submitAsk()
        precondition(controller.readingInProgress && !controller.askVisible)
        precondition(controller.askQuestionPreview == "Send fixture")
        try? await Task.sleep(for: .milliseconds(200))
        controller.smokeSnapshot("ask-send-transition")
        controller.dismiss(restoreFocus: false)
        precondition(controller.askQuestionPreview == nil)
        source.close()
        print("PASS: compact/growing/capped/shrinking Ask, focus, Shift-Return, refinement/restore, cancellation, failure and explicit send")
        NSApp.terminate(nil)
        return
      }
      if CommandLine.arguments.contains("--ask-focus-only") {
        // A source-like window with an editable field, without touching any user app.
        let source = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 320, height: 100),
          styleMask: [.titled], backing: .buffered, defer: false)
        source.isReleasedWhenClosed = false
        let sourceInput = NSTextField(string: "Source unchanged")
        sourceInput.frame = NSRect(x: 20, y: 30, width: 280, height: 30)
        source.contentView?.addSubview(sourceInput)
        source.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        source.makeFirstResponder(sourceInput)
        try? await Task.sleep(for: .milliseconds(150))
        // Unlike showHome(), this retains the .noSelection capture from the shortcut.
        controller.smokeCapturedEmptyHome()
        controller.runHomeAction(.ask)
        try? await Task.sleep(for: .milliseconds(200))
        let askWindow = NSApp.keyWindow
        precondition(askWindow !== source && askWindow?.firstResponder is NSTextView)
        for _ in 0..<8 {
          try? await Task.sleep(for: .milliseconds(500))
          precondition(controller.askVisible && controller.smokeVisible,
            "Captured-empty Ask must not expire while typing")
          precondition(NSApp.keyWindow === askWindow, "Ask must keep keyboard focus")
          controller.smokeType("a")
        }
        precondition(controller.askQuery == "aaaaaaaa")
        precondition(sourceInput.stringValue == "Source unchanged")
        let editor = askWindow?.firstResponder as! NSTextView
        editor.setSelectedRange(NSRange(location: 3, length: 0))
        controller.smokeType("b")
        precondition(controller.askQuery == "aaabaaaaa", "Typing must preserve the caret")
        controller.smokeNavigationKey(53)
        precondition(controller.homeVisible && !controller.askVisible)
        controller.runHomeAction(.ask)
        try? await Task.sleep(for: .milliseconds(200))
        precondition(NSApp.keyWindow?.firstResponder is NSTextView)
        source.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(150))
        precondition(controller.smokeVisible && controller.askVisible,
          "Ask must remain open after a deliberate window change")
        controller.dismiss(restoreFocus: false)
        for editable in [false, true] {
          controller.presentSmokeStatus(.selected("Synthetic bubble selection"))
          if editable { controller.smokeMakeSelectionEditable() }
          controller.smokeRestoreWindowDelegate()
          source.makeKeyAndOrderFront(nil)
          try? await Task.sleep(for: .milliseconds(150))
          precondition(!controller.smokeVisible, "Action bubbles must dismiss regardless of source editability")
        }
        controller.smokeCapturedEmptyHome()
        source.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(150))
        precondition(!controller.smokeVisible, "Home bubbles must dismiss on focus loss")
        precondition(NSApp.keyWindow === source)
        controller.presentSmokeStatus(.unavailable)
        precondition(NSApp.keyWindow === source, "A notice must not steal focus")
        controller.smokeCapturedEmptyHome()
        controller.runHomeAction(.ask)
        try? await Task.sleep(for: .seconds(3))
        precondition(controller.askVisible && controller.smokeVisible,
          "Entering Ask must cancel an earlier notice's expiry")
        controller.dismiss(restoreFocus: false)
        source.makeKeyAndOrderFront(nil)
        controller.presentSmokeStatus(.unavailable)
        try? await Task.sleep(for: .seconds(3))
        precondition(!controller.smokeVisible, "Actual transient notices must still expire")
        precondition(sourceInput.stringValue == "Source unchanged")
        source.close()
        print("PASS: captured-empty Ask keeps native focus beyond 2.5s, typing/caret, source unchanged, back/reopen, deliberate window change and notice expiry/cancellation")
        NSApp.terminate(nil)
        return
      }
      if CommandLine.arguments.contains("--reading-only") {
        controller.presentSmokeStatus(.selected("Correct fixture"))
        controller.choose(.fix)
        try? await Task.sleep(for: .milliseconds(400))
        controller.smokeSnapshot("mode-orbit-correct")
        controller.dismiss(restoreFocus: false)
        controller.showHome(); controller.smokeIsolate()
        precondition(controller.homeActions.contains(.ask))
        controller.runHomeAction(.ask)
        try? await Task.sleep(for: .milliseconds(150))
        precondition(controller.askVisible && !controller.homeVisible)
        precondition(NSApp.keyWindow?.firstResponder is NSTextView, "Ask input must focus")
        controller.smokeSnapshot("ask-input")
        controller.smokeNavigationKey(53)
        precondition(controller.homeVisible && !controller.askVisible)
        controller.runHomeAction(.ask)
        controller.askQuery = "What is a cache?"
        controller.smokeReturnKey()
        precondition(controller.readingInProgress && controller.explanationText == "")
        let frame = controller.smokeFrame
        let before = NSPasteboard.general.changeCount
        controller.copyExplanation()
        precondition(NSPasteboard.general.changeCount == before)
        try? await Task.sleep(for: .milliseconds(400))
        precondition(controller.explanationText == "Partial fixture" && controller.readingInProgress)
        precondition(controller.smokeFrame!.width == frame!.width && controller.smokeFrame!.height < frame!.height)
        controller.smokeSnapshot("ask-progress")
        controller.smokeReturnKey()
        precondition(controller.smokePasteAttempts.isEmpty)
        try? await Task.sleep(for: .milliseconds(500))
        precondition(!controller.readingInProgress && controller.readingError == nil)
        precondition(controller.explanationText == "Complete fixture [OpenAI](https://openai.com)")
        precondition(controller.smokeFrame!.width == frame!.width && controller.explanationContentHeight == 22)
        let compactFrame = controller.smokeFrame
        controller.smokeSnapshot("ask-complete")
        precondition(controller.explanationContentHeight == 22, "Short answer must have no empty viewport")
        let readingTop = controller.smokeFrame!.maxY
        controller.smokeFitReading(String(repeating: "A longer answer with useful details. ", count: 60))
        precondition(controller.explanationContentHeight == 200)
        precondition(controller.smokeFrame!.maxY == readingTop, "Reading growth must preserve the top")
        try? await Task.sleep(for: .milliseconds(150))
        controller.smokeSnapshot("ask-long-answer")
        controller.smokeFitReading("Complete fixture [OpenAI](https://openai.com)")
        precondition(controller.smokeFrame == compactFrame, "Card must shrink to fit a short answer")
        try? await Task.sleep(for: .milliseconds(150))
        controller.copyExplanation()
        precondition(NSPasteboard.general.string(forType: .string) == controller.explanationText)
        @MainActor func readingTextView(in view: NSView) -> NSTextView? {
          if let text = view as? NSTextView, !text.isEditable { return text }
          for child in view.subviews {
            if let text = readingTextView(in: child) { return text }
          }
          return nil
        }
        let content = NSApp.keyWindow!.contentView!
        guard let nativeText = readingTextView(in: content) else {
          preconditionFailure("Reading result must use native link handling")
        }
        precondition(nativeText.string == "Complete fixture OpenAI")
        precondition(nativeText.linkTextAttributes?[.cursor] as? NSCursor === NSCursor.pointingHand)
        let link = URL(string: "https://openai.com")!
        precondition(nativeText.textStorage?.attribute(.link, at: 17, effectiveRange: nil) as? URL == link)
        controller.openExplanationLink(URL(string: "file:///tmp/fixture")!)
        precondition(controller.smokeOpenedLinks.isEmpty)
        let handled = nativeText.delegate?.textView?(nativeText, clickedOnLink: link, at: 17)
        precondition(handled == true && controller.smokeOpenedLinks == [link])
        controller.smokeRestoreWindowDelegate()
        let browser = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 200, height: 100),
          styleMask: [.titled], backing: .buffered, defer: false)
        browser.isReleasedWhenClosed = false
        browser.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(100))
        precondition(controller.smokeVisible && controller.explanationText != nil,
          "Opening a source must keep the reading card visible")
        controller.smokeMakeKey()
        browser.close()
        controller.dismiss(restoreFocus: false)
        controller.showHome(); controller.runHomeAction(.ask)
        try? await Task.sleep(for: .milliseconds(100))
        browser.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(100))
        precondition(!controller.smokeVisible, "Keep-open must reset before another invocation")
        browser.close()
        controller.presentSmokeStatus(.selected("Explain fixture"))
        controller.choose(.explain)
        precondition(controller.readingInProgress)
        controller.smokeNavigationKey(53)
        try? await Task.sleep(for: .milliseconds(1000))
        precondition(controller.explanationText == nil && !controller.smokeVisible)
        controller.showHome(); controller.smokeIsolate(); controller.runHomeAction(.ask)
        controller.askQuery = "Stream error fixture"; controller.submitAsk()
        try? await Task.sleep(for: .milliseconds(900))
        precondition(controller.readingError != nil && !controller.readingInProgress)
        let failedCount = NSPasteboard.general.changeCount
        controller.copyExplanation()
        precondition(NSPasteboard.general.changeCount == failedCount)
        controller.dismiss(restoreFocus: false)
        for editable in [false, true] {
          controller.presentSmokeStatus(.selected("Translation fixture"))
          if editable { controller.smokeMakeSelectionEditable() }
          controller.choose(.translate)
          try? await Task.sleep(for: .milliseconds(350))
          precondition(controller.choosingTranslationLanguage)
          controller.translateSelection(to: .french)
          precondition(controller.readingInProgress == !editable)
          try? await Task.sleep(for: .milliseconds(1000))
          if editable { precondition(controller.smokePasteAttempts == ["Corrected"] && controller.explanationText == nil) }
          else { precondition(controller.explanationText == "Corrected" && controller.smokePasteAttempts.isEmpty) }
          controller.dismiss(restoreFocus: false)
        }
        print("PASS: Ask focus/back, fitted short/long progressive card, native links/cursor, keep-open/reset, completion/copy, cancellation, failure and atomic editable translation")
        NSApp.terminate(nil)
        return
      }
      if CommandLine.arguments.contains("--reply-only") {
        for editable in [false, true] {
          controller.presentSmokeStatus(.selected("Can we meet Thursday at 3?"))
          controller.smokeSetReplyContext()
          if editable { controller.smokeMakeSelectionEditable() }
          controller.beginActionSearch(query: "reply")
          controller.smokeReturnKey()
          try? await Task.sleep(for: .milliseconds(900))
          precondition(controller.replyIntents == [.accept, .decline, .alternative])
          precondition(controller.smokePasteAttempts.isEmpty && !controller.replyDrafting)
          precondition(controller.smokeReplyRequests.last?.2 == nil)
          let context = controller.smokeReplyRequests.last?.1
          precondition(context?.nearbyText == "Synthetic nearby context")
          if !editable {
            controller.smokeSnapshot("reply-intents")
            controller.smokeNavigationKey(123)
            precondition(controller.replyIntentIndex == -1, "Reply uses the shared keyboard-accessible Back item")
            controller.smokeReturnKey()
            precondition(controller.state.isSearching && controller.state.searchQuery == "reply" && controller.replyIntents.isEmpty)
            controller.smokeReturnKey()
            try? await Task.sleep(for: .milliseconds(900))
          }
          controller.smokeNavigationKey(124)
          precondition(controller.replyIntentIndex == 1)
          controller.smokeReturnKey()
          controller.smokeReturnKey() // No duplicate drafting while busy.
          try? await Task.sleep(for: .milliseconds(1300))
          precondition(controller.smokeReplyRequests.last?.2 == .decline)
          precondition(controller.smokeReplyRequests.last?.1 == context)
          precondition(controller.smokeReplyRequests.filter { $0.2 != nil }.count == (editable ? 2 : 1))
          if editable {
            precondition(controller.smokePasteAttempts == ["Reply: decline"] && controller.explanationText == nil)
          } else {
            precondition(controller.explanationText == "Reply: decline" && controller.smokePasteAttempts.isEmpty)
            controller.smokeReturnKey()
            precondition(controller.smokePasteAttempts.isEmpty && controller.smokeVisible)
            controller.copyExplanation()
            precondition(NSPasteboard.general.string(forType: .string) == "Reply: decline")
          }
          controller.dismiss(restoreFocus: false)
        }
        controller.smokePasteAttempts.removeAll()
        for duringDraft in [false, true] {
          controller.presentSmokeStatus(.selected("Cancel this reply"))
          controller.beginActionSearch(query: "reply"); controller.smokeReturnKey()
          if duringDraft {
            try? await Task.sleep(for: .milliseconds(900))
            controller.chooseReplyIntent(.accept)
          }
          try? await Task.sleep(for: .milliseconds(320))
          controller.dismiss(restoreFocus: false)
          controller.presentSmokeStatus(.selected("A new selection"))
          try? await Task.sleep(for: .milliseconds(700))
          precondition(controller.replyIntents.isEmpty && controller.explanationText == nil && controller.smokePasteAttempts.isEmpty)
          controller.dismiss(restoreFocus: false)
        }
        controller.presentSmokeStatus(.selected("Not a message"))
        controller.smokeMakeSelectionEditable()
        controller.beginActionSearch(query: "reply"); controller.smokeReturnKey()
        try? await Task.sleep(for: .milliseconds(900))
        precondition(controller.correctionMessage == "Select a message to reply to." && controller.smokePasteAttempts.isEmpty)
        controller.dismiss(restoreFocus: false)
        print("PASS: Reply options/back, frozen context, choice/Return, read/copy, editable dispatch, unsupported input and cancellation in both stages")
        NSApp.terminate(nil)
        return
      }
      if CommandLine.arguments.contains("--search-navigation-only") {
        controller.presentSmokeStatus(.selected("Selection stays intact"))
        let original = controller.selection
        controller.beginActionSearch(query: "e")
        for _ in 0..<20 {
          if (NSApp.keyWindow?.firstResponder as? NSTextView)?.string == "e" { break }
          try? await Task.sleep(for: .milliseconds(50))
        }
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else { preconditionFailure("Search has no editor") }
        let caret = editor.selectedRange()
        let choices = controller.state.suggestions
        precondition(choices.count == 3 && controller.state.selected == choices[0])
        precondition(controller.smokeNavigationKey(124))
        precondition(controller.state.selected == choices[1], "Right must select the next mode")
        controller.smokeNavigationKey(123)
        precondition(controller.state.selected == choices[0], "Left must select the previous mode")
        controller.smokeNavigationKey(123)
        precondition(controller.state.selected == choices[2], "Left must wrap")
        controller.smokeNavigationKey(124)
        precondition(controller.state.selected == choices[0], "Right must wrap")
        controller.smokeNavigationKey(125)
        precondition(controller.state.selected == choices[1])
        controller.smokeNavigationKey(126)
        precondition(controller.state.selected == choices[0])
        for modifier in [NSEvent.ModifierFlags.option, .command, .shift, .control] {
          precondition(!controller.smokeNavigationKey(123, modifiers: modifier), "Modified arrows belong to the editor")
        }
        precondition(controller.state.selected == choices[0] && controller.state.searchQuery == "e")
        precondition(editor.string == "e" && editor.selectedRange() == caret)
        precondition(NSApp.keyWindow?.firstResponder === editor && controller.selection == original)
        controller.updateActionSearch("zzzzz")
        controller.smokeNavigationKey(123); controller.smokeNavigationKey(124); controller.smokeReturnKey()
        precondition(controller.state.executing == nil)
        controller.updateActionSearch("e")
        controller.smokeNavigationKey(124); controller.smokeReturnKey()
        precondition(controller.state.executing == choices[1], "Return must execute the highlighted result")
        controller.dismiss(restoreFocus: false)
        print("PASS: search arrows, wrap, focus/query preservation, modified arrows, empty results and Return dispatch")
        NSApp.terminate(nil)
        return
      }
      if CommandLine.arguments.contains("--search-only") {
        controller.presentSmokeStatus(.selected("Selection stays intact"))
        let original = controller.selection
        precondition(controller.state.actions.contains(.search), "Search is available on the first page")
        controller.smokeSnapshot("page-one")
        precondition(controller.smokeNavigationKey(3, modifiers: .command))
        precondition(controller.state.isSearching && controller.state.page == .main)
        controller.endActionSearch()
        controller.choose(.more)
        precondition(controller.state.suggestions == [.rewrite, .keyPoints, .extractTasks])
        let row = NSHostingView(rootView: HStack(spacing: ActionBubble.spacing) {
          ForEach(controller.state.actions) { action in
            ActionBubble(action: action, selected: false, perform: {})
          }
        }.fixedSize())
        precondition(row.fittingSize.width <= 416, "Second page is clipped")
        try? await Task.sleep(for: .milliseconds(300))
        controller.smokeSnapshot("page-two")
        controller.choose(.search) // Same callback as the magnifying-glass button.
        for _ in 0..<20 {
          if (NSApp.keyWindow?.firstResponder as? NSTextView) != nil { break }
          try? await Task.sleep(for: .milliseconds(50))
        }
        precondition(controller.state.isSearching && NSApp.keyWindow?.frame.height == 92)
        precondition((NSApp.keyWindow?.firstResponder as? NSTextView)?.string == "", "Search must focus immediately")
        controller.smokeType("t")
        controller.smokeType("a")
        controller.smokeType("s")
        try? await Task.sleep(for: .milliseconds(350))
        precondition(controller.state.searchQuery == "tas", "Typing lost characters")
        precondition(controller.state.suggestions == [.extractTasks, .createTasks])
        precondition(controller.selection == original, "Search changed the captured selection")
        controller.smokeSnapshot("results")
        controller.smokeNavigationKey(53)
        precondition(!controller.state.isSearching && controller.state.page == .more)
        precondition(NSApp.keyWindow?.frame.height == 54)
        // Escape leaves the loupe selected; Return reopens it.
        controller.smokeReturnKey()
        precondition(controller.state.isSearching)
        controller.updateActionSearch("zzzzz")
        controller.smokeReturnKey()
        precondition(controller.state.executing == nil && controller.smokeVisible)
        controller.endActionSearch()
        controller.smokeType("t") // Type-to-search seeds the first character.
        controller.smokeType("r") // A second event before the native field has attached.
        try? await Task.sleep(for: .milliseconds(150))
        precondition((NSApp.keyWindow?.firstResponder as? NSTextView)?.string == "tr", "Immediate reopen must create a fresh, focused field")
        precondition(controller.state.searchQuery == "tr")
        controller.updateActionSearch("translate")
        controller.smokeReturnKey()
        try? await Task.sleep(for: .milliseconds(350))
        precondition(controller.choosingTranslationLanguage && NSApp.keyWindow?.frame.height == 54)
        controller.backFromTranslation()
        try? await Task.sleep(for: .milliseconds(150))
        precondition(controller.state.isSearching && controller.state.searchQuery == "translate")
        precondition((NSApp.keyWindow?.firstResponder as? NSTextView)?.string == "translate")
        controller.endActionSearch()
        controller.beginActionSearch(query: "tasks")
        controller.smokeMakeSelectionEditable()
        controller.smokeReturnKey()
        try? await Task.sleep(for: .milliseconds(1000))
        precondition(controller.smokePasteAttempts == ["Corrected\n- Check the links"])
        controller.dismiss(restoreFocus: false)
        controller.presentSmokeStatus(.selected("120"))
        precondition(!controller.state.isSearching && controller.state.searchQuery.isEmpty)
        controller.choose(.search)
        controller.updateActionSearch("math")
        controller.smokeReturnKey()
        for _ in 0..<30 {
          if (NSApp.keyWindow?.firstResponder as? NSTextView)?.string == "120" { break }
          try? await Task.sleep(for: .milliseconds(50))
        }
        controller.smokeSnapshot("calculator")
        precondition(controller.calculatorValue == 120 && (NSApp.keyWindow?.firstResponder as? NSTextView)?.string == "120",
                     "Calculator value=\(String(describing: controller.calculatorValue)), executing=\(String(describing: controller.state.executing)), editor=\(String(describing: (NSApp.keyWindow?.firstResponder as? NSTextView)?.string))")
        controller.dismiss(restoreFocus: false)
        print("PASS: two pages, search click/Return/type, native input focus/editing, empty results, options/back, editable dispatch, calculator and reset")
        NSApp.terminate(nil)
        return
      }
      if CommandLine.arguments.contains("--extract-tasks-only") {
        for editable in [false, true] {
          controller.presentSmokeStatus(.selected("Maya must send the quote. Check the links."))
          if editable { controller.smokeMakeSelectionEditable() }
          controller.choose(.more)
          controller.choose(.back)
          precondition(NSApp.keyWindow?.frame.width == 440)
          controller.smokeNavigationKey(48) // Tab opens More.
          precondition(controller.state.page == .more)
          controller.smokeNavigationKey(53) // Escape returns to the original width.
          precondition(controller.state.page == .main && NSApp.keyWindow?.frame.width == 440)
          controller.choose(.more)
          let row = NSHostingView(rootView: HStack(spacing: 10) {
            ForEach(controller.state.actions) { action in
              ActionBubble(action: action, selected: action == .extractTasks, perform: {})
            }
          }.fixedSize())
          precondition(row.fittingSize.width <= (NSApp.keyWindow?.frame.width ?? 0) - 2 * PanelPlacement.contentInset,
                       "More clips the new action")
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString("extract tasks sentinel", forType: .string)
          controller.choose(.extractTasks)
          try? await Task.sleep(for: .milliseconds(1000))
          precondition(controller.state.executing == .extractTasks)
          let result = "Corrected\n- Check the links"
          if editable {
            precondition(controller.explanationText == nil && controller.correctionText == result)
            precondition(controller.smokePasteAttempts == [result], "Editable tasks must use the shared replacement path")
            controller.dismiss(restoreFocus: false)
          } else {
            precondition(controller.explanationText == result)
            controller.smokeReturnKey()
            precondition(!controller.isPasting && controller.smokeVisible && controller.smokePasteAttempts.isEmpty)
            precondition(NSPasteboard.general.string(forType: .string) == "extract tasks sentinel")
            controller.copyExplanation()
            precondition(NSPasteboard.general.string(forType: .string) == result)
            controller.closeExplanation()
            try? await Task.sleep(for: .milliseconds(250))
            precondition(!controller.smokeVisible)
          }
        }
        controller.smokePasteAttempts.removeAll()
        controller.presentSmokeStatus(.selected("No pending tasks fixture"))
        controller.smokeMakeSelectionEditable()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("empty tasks sentinel", forType: .string)
        controller.choose(.more)
        controller.choose(.extractTasks)
        try? await Task.sleep(for: .milliseconds(1000))
        precondition(controller.explanationText == "No tasks found." && controller.correctionText == nil)
        controller.smokeReturnKey()
        precondition(controller.smokePasteAttempts.isEmpty && !controller.isPasting)
        precondition(NSPasteboard.general.string(forType: .string) == "empty tasks sentinel")
        controller.dismiss(restoreFocus: false)
        controller.presentSmokeStatus(.selected("Cancelled extraction"))
        controller.smokeMakeSelectionEditable()
        controller.choose(.more)
        controller.choose(.extractTasks)
        try? await Task.sleep(for: .milliseconds(310))
        controller.dismiss(restoreFocus: false)
        controller.presentSmokeStatus(.selected("New selection"))
        try? await Task.sleep(for: .milliseconds(700))
        precondition(controller.explanationText == nil && controller.smokePasteAttempts.isEmpty)
        controller.dismiss(restoreFocus: false)
        print("PASS: Extract tasks replacement dispatch, reading card, empty result and cancellation (synthetic provider)")
        NSApp.terminate(nil)
        return
      }
      for cycle in 1...3 {
        for status in [SelectionReadout.Status.noSelection, .permissionRequired, .selected("Test selection")] {
          controller.presentSmokeStatus(status)
          try? await Task.sleep(for: .milliseconds(500))
          precondition(controller.smokeVisible, "Panel did not remain visible")
          if case .selected = status {
            controller.choose(.more)
            try? await Task.sleep(for: .milliseconds(250))
            precondition(controller.smokeVisible)
            controller.choose(.back)
            precondition(controller.state.selected == .explain, "Back changed the frozen primary action")
            controller.choose(.translate)
            if cycle == 2 {
              controller.dismiss(restoreFocus: false)
              controller.presentSmokeStatus(.selected("Reopened during fold"))
              try? await Task.sleep(for: .milliseconds(700))
              precondition(controller.smokeVisible && !controller.choosingTranslationLanguage,
                           "Previous execution affected the reopened panel")
            } else {
              try? await Task.sleep(for: .milliseconds(400))
              precondition(controller.smokeVisible && controller.choosingTranslationLanguage,
                           "Translation language selection did not open")
            }
          }
          controller.dismiss(restoreFocus: false)
          try? await Task.sleep(for: .milliseconds(150))
        }
        print("Panel cycle \(cycle) passed")
      }
      controller.presentSmokeStatus(.selected("120"))
      controller.choose(.calculate)
      // Wait for the real focus state, not a fixed delay barely longer than the fold.
      for _ in 0..<25 {
        if (NSApplication.shared.keyWindow?.firstResponder as? NSTextView)?.string == "120" { break }
        try? await Task.sleep(for: .milliseconds(100))
      }
      precondition(controller.smokeVisible && controller.calculatorValue == 120, "Calculator did not open")
      let editor = NSApplication.shared.keyWindow?.firstResponder as? NSTextView
      precondition(editor?.string == "120", "Calculator input is not focused and prefilled")
      precondition(editor?.selectedRange == NSRange(location: 3, length: 0), "Cursor must append to the selected number")
      var submits = 0
      let coordinator = CalculationInput.Coordinator(text: .constant("120 / 4"), submit: { submits += 1 })
      let handled = coordinator.control(NSTextField(), textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
      precondition(handled && submits == 1, "Enter must trigger the explicit paste action once")
      let formatter = CalculationInputFormatter()
      precondition(!formatter.isPartialStringValid("120a", newEditingString: nil, errorDescription: nil))
      precondition(formatter.isPartialStringValid("120 / 4", newEditingString: nil, errorDescription: nil))
      controller.closeCalculator()
      precondition(controller.activeShortcut == "esc" && controller.smokeVisible)
      try? await Task.sleep(for: .milliseconds(140))
      precondition(controller.closing && controller.smokeVisible, "Close must animate before hiding")
      controller.dismiss(restoreFocus: false)
      controller.presentSmokeStatus(.selected("Reopened during close"))
      try? await Task.sleep(for: .milliseconds(250))
      precondition(controller.smokeVisible && !controller.closing && controller.activeShortcut == nil,
                   "Interrupted close affected the next panel")
      controller.dismiss(restoreFocus: false)
      controller.presentSmokeStatus(.selected("120"))
      controller.choose(.calculate)
      try? await Task.sleep(for: .milliseconds(500))
      controller.closeCalculator()
      try? await Task.sleep(for: .milliseconds(400))
      precondition(!controller.smokeVisible, "Animated close did not finish")
      precondition(controller.calculatorValue == nil, "Calculator value leaked into next invocation")
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString("cancel sentinel", forType: .string)
      controller.presentSmokeStatus(.selected("Needs correction"))
      controller.choose(.fix)
      try? await Task.sleep(for: .milliseconds(330))
      controller.dismiss(restoreFocus: false)
      controller.presentSmokeStatus(.selected("New selection"))
      try? await Task.sleep(for: .milliseconds(850))
      precondition(controller.smokeVisible && controller.correctionText == nil && controller.correctionMessage == nil,
                   "Cancelled correction leaked into a new invocation")
      precondition(NSPasteboard.general.string(forType: .string) == "cancel sentinel",
                   "Cancelled correction overwrote the clipboard")
      controller.dismiss(restoreFocus: false)
      for text in ["Needs correction", "unchanged"] {
        controller.presentSmokeStatus(.selected(text))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("correct reading sentinel", forType: .string)
        controller.choose(.fix)
        try? await Task.sleep(for: .milliseconds(1000))
        precondition(controller.smokeVisible && !controller.isPasting && controller.explanationText == "Corrected")
        precondition(NSPasteboard.general.string(forType: .string) == "correct reading sentinel")
        controller.copyExplanation()
        precondition(NSPasteboard.general.string(forType: .string) == "Corrected")
        controller.dismiss(restoreFocus: false)
      }
      controller.presentSmokeStatus(.selected("A concept"))
      controller.choose(.explain)
      for _ in 0..<30 {
        if controller.explanationText?.isEmpty == false && !controller.readingInProgress { break }
        try? await Task.sleep(for: .milliseconds(100))
      }
      precondition(controller.smokeVisible && controller.explanationText == "Complete fixture [OpenAI](https://openai.com)")
      precondition(!controller.isPasting && controller.correctionText == nil,
                   "Explanation must never enter the replacement path")
      controller.copyExplanation()
      precondition(controller.activeShortcut == "⌘C" && controller.smokeVisible)
      controller.closeExplanation()
      try? await Task.sleep(for: .milliseconds(250))
      precondition(!controller.smokeVisible && controller.explanationText == nil)
      controller.presentSmokeStatus(.selected("Cancelled explanation"))
      controller.choose(.explain)
      try? await Task.sleep(for: .milliseconds(330))
      controller.closeExplanation()
      try? await Task.sleep(for: .milliseconds(200))
      controller.presentSmokeStatus(.selected("Reopened after explanation"))
      try? await Task.sleep(for: .milliseconds(400))
      precondition(controller.smokeVisible && controller.explanationText == nil)
      controller.dismiss(restoreFocus: false)
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString("translation sentinel", forType: .string)
      controller.presentSmokeStatus(.selected("Translate this"))
      controller.choose(.translate)
      try? await Task.sleep(for: .milliseconds(400))
      precondition(controller.choosingTranslationLanguage)
      precondition(NSPasteboard.general.string(forType: .string) == "translation sentinel")
      controller.translateSelection(to: .french)
      precondition(!controller.choosingTranslationLanguage)
      for _ in 0..<30 {
        if controller.explanationText?.isEmpty == false && !controller.readingInProgress { break }
        try? await Task.sleep(for: .milliseconds(100))
      }
      precondition(controller.smokeVisible && !controller.isPasting)
      precondition(controller.explanationText == "Corrected" && controller.correctionText == nil)
      precondition(NSPasteboard.general.string(forType: .string) == "translation sentinel",
                   "Reading a translation must not overwrite the clipboard")
      controller.copyExplanation()
      precondition(NSPasteboard.general.string(forType: .string) == "Corrected")
      precondition(controller.smokeVisible && controller.activeShortcut == "⌘C")
      controller.closeExplanation()
      try? await Task.sleep(for: .milliseconds(250))
      precondition(!controller.smokeVisible && controller.explanationText == nil)
      controller.presentSmokeStatus(.selected("Cancel translation"))
      controller.choose(.translate)
      try? await Task.sleep(for: .milliseconds(350))
      controller.translateSelection(to: .english)
      try? await Task.sleep(for: .milliseconds(330))
      controller.dismiss(restoreFocus: false)
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString("cancel translation sentinel", forType: .string)
      controller.presentSmokeStatus(.selected("New text"))
      try? await Task.sleep(for: .milliseconds(500))
      precondition(controller.smokeVisible && controller.correctionText == nil && controller.explanationText == nil)
      precondition(NSPasteboard.general.string(forType: .string) == "cancel translation sentinel")
      controller.dismiss(restoreFocus: false)
      controller.presentSmokeStatus(.selected("A message to rewrite"))
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString("rewrite sentinel", forType: .string)
      controller.choose(.more)
      controller.choose(.rewrite)
      controller.smokeReturnKey()
      try? await Task.sleep(for: .milliseconds(1000))
      precondition(controller.state.executing == .rewrite && controller.explanationText == "Corrected")
      precondition(NSPasteboard.general.string(forType: .string) == "rewrite sentinel", "Read-only Rewrite copied automatically")
      controller.copyExplanation()
      precondition(NSPasteboard.general.string(forType: .string) == "Corrected")
      controller.dismiss(restoreFocus: false)
      controller.presentSmokeStatus(.selected("Cancel rewrite"))
      controller.choose(.more)
      controller.choose(.rewrite)
      controller.smokeReturnKey()
      try? await Task.sleep(for: .milliseconds(310))
      controller.dismiss(restoreFocus: false)
      controller.presentSmokeStatus(.selected("New selection"))
      try? await Task.sleep(for: .milliseconds(700))
      precondition(controller.explanationText == nil && controller.smokeVisible)
      controller.dismiss(restoreFocus: false)
      for editable in [false, true] {
        controller.presentSmokeStatus(.selected("A passage with key ideas"))
        if editable { controller.smokeMakeSelectionEditable() }
        precondition(controller.selection?.canPaste == editable)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("key points sentinel", forType: .string)
        controller.choose(.more)
        controller.choose(.keyPoints)
        try? await Task.sleep(for: .milliseconds(1000))
        precondition(controller.state.executing == .keyPoints)
        let result = "Corrected\n- Second idea"
        if editable {
          precondition(controller.explanationText == nil && controller.correctionText == result)
          precondition(controller.smokePasteAttempts == [result], "Editable Key points did not dispatch to the shared replacement path")
        } else {
          precondition(controller.explanationText == result)
          controller.smokeReturnKey()
          precondition(!controller.isPasting && controller.smokeVisible && controller.smokePasteAttempts.isEmpty)
          precondition(NSPasteboard.general.string(forType: .string) == "key points sentinel", "Read-only Key points wrote the clipboard automatically")
          controller.copyExplanation()
          precondition(NSPasteboard.general.string(forType: .string) == result)
        }
        controller.dismiss(restoreFocus: false)
      }
      controller.smokePasteAttempts.removeAll()
      controller.presentSmokeStatus(.selected("Cancel key points"))
      controller.smokeMakeSelectionEditable()
      controller.choose(.more)
      controller.choose(.keyPoints)
      try? await Task.sleep(for: .milliseconds(310))
      controller.dismiss(restoreFocus: false)
      controller.presentSmokeStatus(.selected("New selection"))
      try? await Task.sleep(for: .milliseconds(700))
      precondition(controller.explanationText == nil && controller.smokeVisible && controller.smokePasteAttempts.isEmpty)
      controller.dismiss(restoreFocus: false)
      if CommandLine.arguments.contains("--actions-only") {
        print("PASS: action panels, translation options, result delivery and cancellation (synthetic provider)")
        NSApp.terminate(nil)
        return
      }
      controller.presentSmokeStatus(.noSelection)
      try? await Task.sleep(for: .seconds(3))
      precondition(!controller.smokeVisible, "Transient notice did not close")
      controller.showHome()
      try? await Task.sleep(for: .milliseconds(400))
      precondition(controller.homeVisible && controller.smokeVisible)
      precondition(NSApp.keyWindow?.frame.height == 54, "Home must retain the compact bar height")
      precondition(controller.homeActions == [.clipboard, .createHabit, .habits])
      let clipboardRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      let clipboardBoard = NSPasteboard.withUniqueName()
      let clipboardDefaults = UserDefaults(suiteName: "tero-ui-clipboard-\(UUID().uuidString)")!
      let clipboardStore = ClipboardStore(url: clipboardRoot.appendingPathComponent("history.json"),
                                          defaults: clipboardDefaults, pasteboard: clipboardBoard)
      clipboardBoard.clearContents()
      clipboardBoard.setString("UI clipboard fixture", forType: .string)
      clipboardStore.poll()
      controller.clipboardStore = clipboardStore
      controller.runHomeAction(.clipboard)
      try? await Task.sleep(for: .milliseconds(300))
      precondition(controller.clipboardVisible && !controller.homeVisible)
      precondition(controller.clipboardEntries.count == 1 && !controller.clipboardCanPaste)
      precondition(NSApp.keyWindow?.firstResponder is NSTextView)
      if let view = NSApp.keyWindow?.contentView,
         let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/tero-clipboard-preview.png"))
      }
      controller.useClipboardEntry(paste: false)
      precondition(clipboardBoard.string(forType: .string) == "UI clipboard fixture")
      controller.clipboardQuery = "missing"
      precondition(controller.clipboardEntries.isEmpty)
      controller.clipboardQuery = ""
      let previewFile = clipboardRoot.appendingPathComponent("preview.txt")
      try? Data("A synthetic Quick Look preview.".utf8).write(to: previewFile)
      clipboardStore.browsing = false
      clipboardBoard.clearContents()
      clipboardBoard.writeObjects([previewFile as NSURL])
      clipboardStore.poll()
      clipboardStore.browsing = true
      controller.resetClipboardSelection()
      try? await Task.sleep(for: .milliseconds(700))
      @MainActor func quickLook(in view: NSView) -> QLPreviewView? {
        if let preview = view as? QLPreviewView { return preview }
        return view.subviews.compactMap { quickLook(in: $0) }.first
      }
      if let rootView = NSApp.keyWindow?.contentView, let preview = quickLook(in: rootView) {
        precondition(preview.previewItem != nil && !preview.autostarts)
      } else { preconditionFailure("Missing embedded Quick Look preview") }
      let dragURLs = [previewFile, clipboardRoot.appendingPathComponent("second.txt")]
      try? Data("Second drag fixture".utf8).write(to: dragURLs[1])
      let dragItems = ClipboardFileDragView.draggingItems(for: dragURLs, at: .zero)
      precondition(dragItems.count == 2)
      precondition((dragItems[0].item as? NSURL)?.path == dragURLs[0].path)
      precondition((dragItems[1].item as? NSURL)?.path == dragURLs[1].path)
      controller.beginClipboardDrag(controller.selectedClipboardEntry!)
      precondition(controller.clipboardDragging && !controller.smokeVisible)
      controller.dismiss(restoreFocus: false)
      precondition(controller.clipboardVisible, "Focus loss must not destroy an active drag")
      controller.endClipboardDrag(false)
      precondition(!controller.clipboardDragging && controller.smokeVisible)
      controller.beginClipboardDrag(controller.selectedClipboardEntry!)
      controller.endClipboardDrag(true)
      precondition(!controller.clipboardDragging && !controller.clipboardVisible && !clipboardStore.browsing)
      controller.showHome()
      precondition(controller.homeVisible && !controller.clipboardVisible && !clipboardStore.browsing)
      clipboardStore.clear()
      clipboardBoard.releaseGlobally()
      try? FileManager.default.removeItem(at: clipboardRoot)
      var routedAction: HomeAction?
      controller.onHomeAction = { routedAction = $0 }
      controller.runHomeAction(.habits)
      precondition(routedAction == .habits && !controller.smokeVisible)
      controller.showHome()
      precondition(controller.homeSelectedIndex == 0)
      controller.dismiss(restoreFocus: false)
      print("PASS: compact home/routing/reset and isolated clipboard search/copy/back; 9 openings, content switches, More, fold, interrupted execution, dismissals, cancelled correction, correction results, explanation/copy/close/cancellation, transient timeout")
      app.terminate(nil)
    }

  }
}

@main struct SmokeApp: App {
 @NSApplicationDelegateAdaptor(SmokeDelegate.self) private var delegate
 var body: some Scene { Settings { EmptyView() } }
}
