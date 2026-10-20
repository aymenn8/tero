import AppKit
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let controller = PanelController()
    private let shortcuts = ShortcutRegistry.shared
    private lazy var habitsWindow = HabitsWindowController()
    private var statusItem: NSStatusItem?
    private var planMenuItem: NSMenuItem?
    private var usageMenuItem: NSMenuItem?
    private var contextInspector: ContextInspectorPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if Bundle.main.isTeroDevBuild,
           (CommandLine.arguments.contains("--test-reading-stream") || CommandLine.arguments.contains("--test-ask-web")) {
            // Two fixed synthetic questions only; no recorder or selected user content.
            Task {
                guard let credential = await GatewayAccess.credential() else { print("FAIL: reading credential unavailable"); exit(1) }
                do {
                    let webOnly = CommandLine.arguments.contains("--test-ask-web")
                    for action in webOnly ? ["ask"] : ["ask", "explain"] {
                        var updates = 0
                        let question = webOnly ? "Cherche une actualité publiée cette semaine sur le site officiel de la NASA. Résume en deux phrases et cite la source."
                            : action == "ask" ? "En deux phrases, quelle différence entre RAM et SSD ?"
                            : "A cache stores reusable data to avoid repeating expensive work."
                        let text = try await CorrectionClient().reading(question, action: action,
                          language: .english, requestID: UUID(), credential: credential) { _ in updates += 1 }
                        guard updates > 0, !text.isEmpty else { print("FAIL: no progressive output"); exit(1) }
                        if webOnly && !text.contains("[1 ·") { print("FAIL: no provider citation returned"); exit(1) }
                        print("PASS: live \(action), updates=\(updates), characters=\(text.count)")
                        print("Synthetic answer: \(text)")
                    }
                    exit(0)
                } catch { print("FAIL: live reading \((error as? CorrectionClient.Failure)?.errorDescription ?? "request failed")"); exit(1) }
            }
            return
        }
        if Bundle.main.isTeroDevBuild,
           let flag = CommandLine.arguments.firstIndex(of: "--test-selection-fixture") {
            // Only the disposable synthetic host is accepted. No recorder, inspector,
            // hotkey, AI request or user selection logging in this regression mode.
            guard CommandLine.arguments.indices.contains(flag + 2),
                  let pid = Int32(CommandLine.arguments[flag + 1]),
                  let host = NSRunningApplication(processIdentifier: pid),
                  host.bundleIdentifier == "com.tero.selection-fixture" else { exit(1) }
            let scenario = CommandLine.arguments[flag + 2]
            Task {
                let engine = SelectionEngine()
                if scenario == "prewarmed-editable" {
                    await engine.prepareAccessibility(processIdentifier: pid)
                    await engine.prepareAccessibility(processIdentifier: pid)
                }
                let result = await engine.capture(applicationName: "Selection fixture", processIdentifier: pid,
                                                  applicationID: host.bundleIdentifier)
                let passed: Bool
                switch scenario {
                case "slow-editable", "transient", "prewarmed-editable":
                    let validTarget = await engine.validatesPasteTarget(result)
                    passed = result.status == .selected("Tero synthetic selection fixture") && validTarget && !result.opensHome
                case "slow-reading", "split-focus", "web-reading", "range-reading":
                    passed = result.status == .selected("Tero synthetic selection fixture") && !result.canPaste && !result.opensHome
                case "empty": passed = result.status == .noSelection && result.opensHome && result.canInsertClipboard
                case "secure": passed = result.status == .protectedField && !result.opensHome && result.context?.nearbyText == nil
                case "unsupported": passed = result.status == .unsupported && !result.opensHome
                default: passed = false
                }
                print(passed ? "PASS: selection fixture \(scenario)" : "FAIL: selection fixture \(scenario)")
                if !passed {
                    let status = result.hasSelection ? "selected" : result.opensHome ? "empty" : result.status == .protectedField ? "protected" : result.status == .unsupported ? "unsupported" : result.status == .permissionRequired ? "permission" : "unavailable"
                    print("Fixture diagnostics: \(status), role=\(result.context?.elementRole ?? "unknown"), editable=\(result.metadata?.isEditable == true), range=\(String(describing: result.metadata?.range)), target=\(result.targetID != nil), capture=\(result.context?.capture.rawValue ?? "none")")
                }
                exit(passed ? 0 : 1)
            }
            return
        }
        if Bundle.main.isTeroDevBuild, CommandLine.arguments.contains("--configure-ai") {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            let token = String(data: data, encoding: .utf8) ?? ""
            let saved = GatewayCredential.save(token)
            print(saved ? "Gateway credential saved." : "Gateway credential failed.")
            exit(saved ? 0 : 1)
        }
        if Bundle.main.isTeroDevBuild, (CommandLine.arguments.contains("--test-ai") || CommandLine.arguments.contains("--evaluate-fixtures")) {
            Task {
                guard let credential = await GatewayAccess.credential() else { print("Missing gateway credential"); exit(1) }
                do {
                    if let flag = CommandLine.arguments.firstIndex(of: "--evaluate-fixtures"),
                       CommandLine.arguments.indices.contains(flag + 1) {
                        struct Fixture: Decodable { let id: String; let input: String; let expected_text: String?; let action: String?; let responseLanguage: String?; let targetLanguage: String?; let replyIntent: ReplyIntent?; let replyContext: ReplyContext?; let filePath: String?; let filePaths: [String]?; let style: TextStyle?; let refinement: String? }
                        struct Fixtures: Decodable { let cases: [Fixture] }
                        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[flag + 1]))
                        let fixtures = try JSONDecoder().decode(Fixtures.self, from: data)
                        guard fixtures.cases.count <= 12 else { exit(1) }
                        for fixture in fixtures.cases {
                            let result: String
                            var replyChoices: [ReplyIntent]?
                            if fixture.action == "rename_files", let paths = fixture.filePaths {
                                guard !paths.isEmpty, paths.count <= 20 else { throw CorrectionClient.Failure.invalid }
                                let urls = paths.map { URL(fileURLWithPath: $0) }
                                let snapshots = try urls.map(LocalFileIO.Snapshot.init)
                                let inputs = try await FileSummaryReader().namingInputs(urls, snapshots: snapshots)
                                let names = try await CorrectionClient().renameFiles(inputs, requestID: UUID(), credential: credential)
                                result = String(decoding: try JSONEncoder().encode(names), as: UTF8.self)
                            } else if fixture.action == "summarize_file", let path = fixture.filePath {
                                let file = try await FileSummaryReader().prepare(URL(fileURLWithPath: path))
                                result = try await CorrectionClient().reading("Summarize the selected file.", action: "summarize_file",
                                    language: fixture.responseLanguage.flatMap(ResponseLanguage.init(rawValue:)) ?? .english,
                                    requestID: UUID(), credential: credential, update: { _ in }, file: file)
                            } else if fixture.action == "shop_rank" {
                                let selection = SelectionReadout(applicationName: "Synthetic Messages", processIdentifier: 0, status: .selected(fixture.input))
                                guard let context = RankingContext(RecommendationContext(selection: selection, applicationID: nil)) else { throw CorrectionClient.Failure.invalid }
                                let ranked = try await RankingClient().rank(context: context, candidates: ["shop", "explain", "fix"], credential: credential)
                                result = ranked.scores.map { "\($0.id): \($0.score)" }.joined(separator: ", ")
                            } else if fixture.action == "shop" {
                                guard let input = ShoppingRequest.input(request: fixture.input, preferences: fixture.refinement ?? "") else { throw CorrectionClient.Failure.invalid }
                                let products = try await CorrectionClient().shop(input, requestID: UUID(), credential: credential)
                                result = String(decoding: try JSONEncoder().encode(products), as: UTF8.self)
                            } else if fixture.action == "reply" {
                                let choices = try await CorrectionClient().replyOptions(fixture.input, context: fixture.replyContext, requestID: UUID(), credential: credential)
                                replyChoices = choices
                                let intent = fixture.replyIntent ?? choices[0]
                                guard choices.contains(intent) else { throw CorrectionClient.Failure.invalid }
                                result = try await CorrectionClient().reply(fixture.input, context: fixture.replyContext, intent: intent, requestID: UUID(), credential: credential)
                            } else if ["task_plan", "event_plan"].contains(fixture.action ?? "") {
                                let drafts = try await CorrectionClient().plan(fixture.input, destination: fixture.action == "task_plan" ? .reminders : .calendar, context: fixture.replyContext, requestID: UUID(), credential: credential)
                                result = String(decoding: try JSONEncoder().encode(drafts), as: UTF8.self)
                            } else if fixture.action == "habit_design" {
                                let design = try await CorrectionClient().designHabit(fixture.input, current: nil,
                                    requestID: UUID(), credential: credential)
                                result = String(decoding: try JSONEncoder().encode(design), as: UTF8.self)
                            } else if fixture.action == "extract_tasks" {
                                result = try await CorrectionClient().extractTasks(
                                    fixture.input, requestID: UUID(), credential: credential)
                            } else if fixture.action == "key_points" {
                                result = try await CorrectionClient().keyPoints(
                                    fixture.input, requestID: UUID(), credential: credential)
                            } else if fixture.action == "ask_refine" {
                                result = try await CorrectionClient().refinePrompt(
                                    fixture.input, requestID: UUID(), credential: credential)
                            } else if ["rewrite", "tone", "simplify"].contains(fixture.action ?? "") {
                                result = try await CorrectionClient().transform(
                                    fixture.input, action: fixture.action!, style: fixture.style, requestID: UUID(), credential: credential)
                            } else if fixture.action == "result_refine" {
                                result = try await CorrectionClient().reading(fixture.input, action: "result_refine", requestID: UUID(),
                                    credential: credential, update: { _ in }, refinement: fixture.refinement)
                            } else if fixture.action == "check_claim" || fixture.action == "explain" && fixture.replyContext != nil {
                                result = try await CorrectionClient().reading(fixture.input, action: fixture.action!,
                                    language: fixture.responseLanguage.flatMap(ResponseLanguage.init(rawValue:)) ?? .english,
                                    context: fixture.replyContext, requestID: UUID(), credential: credential, update: { _ in })
                            } else if fixture.action == "explain" {
                                result = try await CorrectionClient().explain(
                                    fixture.input, language: fixture.responseLanguage.flatMap(ResponseLanguage.init(rawValue:)) ?? .english, requestID: UUID(), credential: credential)
                            } else if fixture.action == "translate" {
                                result = try await CorrectionClient().translate(
                                    fixture.input, language: fixture.targetLanguage.flatMap(ResponseLanguage.init(rawValue:)) ?? .english,
                                    requestID: UUID(), credential: credential)
                            } else {
                                result = try await CorrectionClient().correct(
                                    fixture.input, requestID: UUID(), credential: credential)
                            }
                            // This explicit CLI mode is only for synthetic fixture files.
                            var row: [String: Any] = ["id": fixture.id, "output": result,
                                "exactMatch": fixture.expected_text.map { $0 == result } as Any? ?? NSNull()]
                            if let replyChoices { row["replyIntents"] = replyChoices.map(\.rawValue) }
                            let encoded = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
                            print(String(decoding: encoded, as: UTF8.self))
                        }
                        exit(0)
                    }
                    let result = try await CorrectionClient().correct(
                        "Les fichiers est pret.", requestID: UUID(), credential: credential)
                    print(result == "Les fichiers sont prêts." ? "PASS: live correction" : "FAIL: unexpected correction")
                    exit(result == "Les fichiers sont prêts." ? 0 : 1)
                } catch { print("FAIL: \(error.localizedDescription)"); exit(1) }
            }
            return
        }
        // Warm the deferred accessibility tree before selection, not after the hotkey.
        NSWorkspace.shared.notificationCenter.addObserver(self,
            selector: #selector(selectionSourceDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        prepareSelectionSource(NSWorkspace.shared.frontmostApplication)
        AppUpdates.shared.start()
        // Development snapshots render Settings only: no clipboard recorder, shortcuts or menu.
        if Bundle.main.isTeroDevBuild, let index = CommandLine.arguments.firstIndex(of: "--snapshot-settings"),
           CommandLine.arguments.indices.contains(index + 1) {
            let folder = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            Task { await habitsWindow.snapshotPages(to: folder); NSApp.terminate(nil) }
            return
        }
        let clipboard = ClipboardStore.live()
        controller.clipboardStore = clipboard
        habitsWindow.clipboard = clipboard
        habitsWindow.setDeveloper = { [weak self] value in self?.setContextInspector(enabled: value) }
        clipboard.start()
        if Bundle.main.isTeroDevBuild {
            NSApp.applicationIconImage = TeroLogoMark.appIcon
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = ""
        let mark = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            context.translateBy(x: rect.minX, y: rect.maxY)
            context.scaleBy(x: rect.width / 32, y: -rect.height / 32)
            context.addPath(TeroLogoMark.symbolPath())
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath(using: .evenOdd)
            context.restoreGState()
            return true
        }
        mark.isTemplate = true
        item.button?.image = mark
        item.button?.setAccessibilityLabel("Tero")
        item.button?.toolTip = "Tero"
        AccountStore.shared.prepare()
        let menu = NSMenu()
        menu.delegate = self
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Tero"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown version"
        let versionItem = NSMenuItem(title: "\(appName) \(version) · Beta", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(.separator())
        let plan = NSMenuItem(title: "Set up AI…", action: #selector(showAISettings), keyEquivalent: "")
        plan.target = self
        menu.addItem(plan)
        planMenuItem = plan
        let usage = NSMenuItem(title: "AI usage unavailable", action: nil, keyEquivalent: "")
        menu.addItem(usage)
        usageMenuItem = usage
        menu.addItem(.separator())
        add("Open Tero", #selector(openHome), to: menu)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        if Bundle.main.isTeroDevBuild {
            controller.onContextChange = { [weak self] context, selection in
                self?.contextInspector?.update(context: context, selection: selection, ranking: self?.controller.rankingDiagnostic ?? "Local", trace: self?.controller.rankingTrace)
                if CommandLine.arguments.contains("--trace-selection"), let context, let selection {
                    let status: String
                    switch selection.status {
                    case .selected: status = "selected"
                    case .noSelection: status = "empty"
                    case .permissionRequired: status = "permission"
                    case .unsupported: status = "unsupported"
                    case .protectedField: status = "protected"
                    case .unavailable: status = "unavailable"
                    }
                    self?.traceSelection(["kind": "capture", "source": context.applicationID ?? "unknown",
                        "status": status, "role": context.elementRole ?? "unknown",
                        "rangeLength": selection.metadata?.range?.length ?? -1,
                        "selectedLength": selection.characterCount ?? 0,
                        "isCodeEditor": [context.elementLabel, context.elementDescription].compactMap { $0 }.contains { $0.localizedCaseInsensitiveContains("code editor") },
                        "hasPlaceholder": context.elementPlaceholder?.isEmpty == false])
                }
            }
            if UserDefaults.standard.bool(forKey: "developerContextInspector") {
                setContextInspector(enabled: true)
            }
        }
        if let updateItem = AppUpdates.shared.menuItem() { menu.addItem(updateItem) }
        add("Send Feedback…", #selector(showFeedback), to: menu)
        menu.addItem(.separator())
        add("Quit Tero", #selector(quit), to: menu)
        item.menu = menu
        statusItem = item
        controller.onHomeAction = { [weak self] action in
            self?.habitsWindow.show(createHabit: action == .createHabit, habitsPage: true)
        }
        shortcuts.onTrigger = { [weak self] target in
            guard let self else { return }
            if OnboardingController.shared.consume(target) { return }
            switch target.id {
            case ShortcutTarget.open.id: controller.toggle()
            case ShortcutTarget.clipboard.id: controller.openHomeShortcut(.clipboard)
            case ShortcutTarget.ask.id: controller.openHomeShortcut(.ask)
            default: if let action = target.action { controller.openModeShortcut(action) }
            }
        }
        shortcuts.start()
        // Dev-only UI fixture: open the action library without changing onboarding state.
        if Bundle.main.isTeroDevBuild, CommandLine.arguments.contains("--test-actions-window") {
            habitsWindow.show(habitsPage: true)
            return
        }
        OnboardingController.shared.onComplete = { }
        // The former account step now introduces bring-your-own AI. It never blocks the tour.
        OnboardingController.shared.isAccountConnected = { AIConfiguration.active != nil }
        OnboardingController.shared.beginAccountSignIn = { [weak self] in self?.habitsWindow.show(aiPage: true) }
        OnboardingController.shared.cancelAccountSignIn = { }
        OnboardingController.shared.accountSignInPending = { false }
        OnboardingController.shared.accountSignInMessage = { nil }
        if Bundle.main.isTeroDevBuild, CommandLine.arguments.contains("--test-onboarding-window") {
            OnboardingController.shared.show()
            return
        }
        if !OnboardingController.shared.progress.isComplete {
            OnboardingController.shared.show()
            return
        }
        let launchEvent = NSAppleEventManager.shared().currentAppleEvent
        let reason = launchEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
        if launchEvent?.eventID == kAEOpenApplication,
           reason != keyAELaunchedAsLogInItem, reason != keyAELaunchedAsServiceItem {
            habitsWindow.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if Bundle.main.isTeroDevBuild, CommandLine.arguments.contains("--test-actions-window") {
            habitsWindow.show(habitsPage: true)
            return false
        }
        if OnboardingController.shared.resumeFromDock() {
            return false
        }
        controller.dismiss(restoreFocus: false)
        habitsWindow.reopen()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func menuWillOpen(_ menu: NSMenu) {
        // The menu shows which AI Tero uses; Tero Pro appears only for subscribers.
        let account = AccountStore.shared
        usageMenuItem?.isHidden = true
        if let ai = AIConfiguration.active {
            planMenuItem?.title = "AI: \(ai.provider.title) · \(ai.model)"
        } else if let usage = account.usage, usage.plan == "pro" {
            planMenuItem?.title = "AI: Tero Pro"
            usageMenuItem?.isHidden = false
            usageMenuItem?.title = "Usage: \(Int(usage.remainingPercent.rounded()))% left"
            usageMenuItem?.toolTip = usage.resetDate.map { "Resets " + $0.formatted(date: .abbreviated, time: .omitted) }
        } else {
            planMenuItem?.title = "Set up AI…"
        }
    }

    // Explicit development diagnosis only: bounded metadata, never text, URLs or titles.
    private var traceCount = 0
    @objc private func selectionSourceDidActivate(_ notification: Notification) {
        prepareSelectionSource(notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
    }

    private func prepareSelectionSource(_ application: NSRunningApplication?) {
        guard let application, application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !application.isTerminated else { return }
        controller.prepareSelectionSource(processIdentifier: application.processIdentifier)
    }

    private func traceSelection(_ fields: [String: Any]) {
        guard Bundle.main.isTeroDevBuild,
              CommandLine.arguments.contains("--trace-selection"),
              traceCount < 12, let data = try? JSONSerialization.data(withJSONObject: fields) else { return }
        traceCount += 1
        FileHandle.standardOutput.write(data + Data("\n".utf8))
    }

    private func setContextInspector(enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "developerContextInspector")
        if !enabled { controller.clearRankingTrace() }
        if enabled {
            let inspector = ContextInspectorPanel()
            contextInspector = inspector
            inspector.update(context: controller.invocationContext, selection: controller.selection, ranking: controller.rankingDiagnostic, trace: controller.rankingTrace)
            inspector.orderFrontRegardless()
        } else {
            contextInspector?.update(context: nil, selection: nil, ranking: "Local")
            contextInspector?.orderOut(nil)
            contextInspector = nil
        }
    }

    private func add(_ title: String, _ action: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    @objc private func showFeedback() { FeedbackWindow.shared.show() }

    @objc private func showSettings() {
        controller.dismiss(restoreFocus: false)
        habitsWindow.show()
    }

    @objc private func openHome() { controller.showHome() }

    @objc private func showAccount() {
        controller.dismiss(restoreFocus: false)
        habitsWindow.show(accountPage: true)
    }

    @objc private func showAISettings() {
        controller.dismiss(restoreFocus: false)
        habitsWindow.show(aiPage: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if OnboardingController.shared.progress.isPresented {
            if urls.contains(where: { AccountStore.shared.receiveCallback($0) }) {
                OnboardingController.shared.show()
                return
            }
            // Do not route account launch links into Settings during onboarding.
            if urls.contains(where: { $0.scheme == Bundle.main.bundleIdentifier && $0.host == "account" }) {
                OnboardingController.shared.show()
                return
            }
        }
        if urls.contains(where: { habitsWindow.receiveAuthCallback($0) }) { return }
        // Website launch links may show Account; only the active web authentication
        // session is allowed to consume a code and its in-memory PKCE verifier.
        if urls.contains(where: {
            $0.scheme == Bundle.main.bundleIdentifier && $0.host == "account"
                && $0.path.isEmpty && $0.query == nil && $0.fragment == nil
        }) { showAccount() }
        if urls.contains(where: {
            $0.scheme == Bundle.main.bundleIdentifier && $0.host == "ai"
                && $0.path.isEmpty && $0.query == nil && $0.fragment == nil
        }) { showAISettings() }
    }
    @objc private func quit() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) { controller.clipboardStore?.stop(); shortcuts.stop() }
}

/// A passive development surface: never participates in the source app's focus.
@MainActor
private final class ContextInspectorPanel: NSPanel {
    private let textView = NSTextView()
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 520, height: 680),
                   styleMask: [.titled, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "Tero · Context inspector"
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        minSize = NSSize(width: 300, height: 240)
        let scroll = NSScrollView(frame: contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        textView.frame = scroll.bounds
        textView.autoresizingMask = [.width]
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        contentView?.addSubview(scroll)
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            setFrameOrigin(NSPoint(x: visible.maxX - 536, y: visible.midY - 340))
        }
    }

    func update(context: InvocationContext?, selection: SelectionReadout?, ranking: String, trace: String? = nil) {
        guard let context else {
            textView.string = "Select something, then press ⌘\\.\n\nLive context · memory only\nCleared when Tero closes.\n\nDisable in Tero → Developer."
            return
        }
        var rows = ["Invocation snapshot · memory only", "Ranking: \(ranking)", "Captured: \(context.capturedAt.formatted(date: .omitted, time: .standard))"]
        func field(_ label: String, _ value: String?) {
            rows.append("\(label): \(value.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown")")
        }
        field("App", context.applicationName)
        field("App ID", context.applicationID)
        field("Capture", context.capture.rawValue)
        if let fileCapture = context.fileCapture {
            field("File selection", fileCapture.rawValue)
            if fileCapture == .permissionRequired {
                rows.append("Allow Tero in System Settings → Privacy & Security → Automation → Finder, then invoke again.")
            } else if fileCapture == .tooMany {
                rows.append("Select up to 100 items.")
            } else if fileCapture == .observed || fileCapture == .partial {
                field("Selected items", String(context.files.count))
                for (index, file) in context.files.enumerated() {
                    rows.append("— Item \(index + 1) —")
                    field("Name", file.name)
                    field("Extension", file.extensionName.isEmpty ? "None" : file.extensionName)
                    field("Type", file.typeIdentifier)
                    field("Folder", file.isDirectory.map { $0 ? "Yes" : "No" })
                    field("Symbolic link", file.isSymbolicLink.map { $0 ? "Yes" : "No" })
                    field("Size", file.isDirectory == true ? "Not measured for folders" : file.byteCount.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) })
                    field("Location", file.parentPath)
                    field("Metadata", file.metadataAvailable ? "Read" : "Unavailable / skipped")
                }
            }
        } else if context.capture != .protectedField {
            field("Window", context.windowTitle)
            field("Website", context.webHost)
            field("Surface", context.surface.rawValue)
            field("Role", context.elementRole)
            field("Subrole", context.elementSubrole)
            field("Label", context.elementLabel)
            field("Description", context.elementDescription)
            field("Placeholder", context.elementPlaceholder)
            field("Containers", context.containers.isEmpty ? nil : context.containers.map {
                $0.role + ($0.label.map { " · " + $0 } ?? "")
            }.joined(separator: " → "))
            field("Missing / limited", context.limitations.isEmpty ? "None reported (not proof of complete context)" : context.limitations.map(\.rawValue).sorted().joined(separator: ", "))
            field("Replace available", selection == nil ? nil : (selection!.canPaste ? "Yes" : "No"))
            field("Selection preview (max 240)", selection?.preview)
            field("Nearby text (bounded)", context.nearbyText)
        } else {
            rows.append("Protected field · content excluded")
        }
        if let trace { rows.append(trace) }
        textView.string = rows.joined(separator: "\n\n")
        textView.scrollToBeginningOfDocument(nil)
    }
}
