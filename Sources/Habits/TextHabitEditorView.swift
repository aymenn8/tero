import SwiftUI
import AppKit

struct TextHabitEditorView: View {
    let store: TextHabitStore
    private let original: TextHabit
    @State private var showsIcons = false
    @State private var customName: String?
    @State private var showsInput = false
    @FocusState private var nameFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft: TextHabit
    @State private var query = ""
    @State private var fileSamples: [FileHabitSample] = []
    @State private var destinationName = ""
    @State private var sample = ""
    @State private var result: String?
    @State private var question: String?
    @State private var previousRequest = ""
    @State private var error: String?
    @State private var run = 0
    @State private var submitted = ""
    @State private var testingOnly = false
    @State private var busy = false
    @State private var progress = ""
    init(store: TextHabitStore, habit: TextHabit) {
        self.store = store; original = habit; _draft = State(initialValue: habit)
        _customName = State(initialValue: habit.isSyncable ? habit.name : nil)
        if let bookmark = habit.destinationBookmark {
            var stale = false
            _destinationName = State(initialValue: (try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale))?.lastPathComponent ?? "")
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TeroModeTitle(title: original.isSyncable ? "Edit habit" : "Create a habit")
                Spacer()
                Button("Close", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly).buttonStyle(TeroQuietButtonStyle()).frame(width: 32, height: 32)
                    .help("Close without saving")
            }.padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 14)
            SettingsDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if draft.instruction.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Create your own action.").font(SettingsStyle.font(20, weight: .semibold))
                            Text("Describe an action. Tero will build it and try it on an example.")
                                .font(SettingsStyle.font(13)).foregroundStyle(SettingsStyle.secondary).lineSpacing(4)
                        }.padding(.top, 12)
                        if busy { loadingState }
                        else {
                            VStack(alignment: .leading, spacing: 14) {
                                Label("Turn notes into a short email", systemImage: "text.alignleft")
                                Label("Rename files in camelCase", systemImage: "doc")
                                Label("Move files to a chosen folder", systemImage: "folder")
                            }.font(SettingsStyle.font(12)).foregroundStyle(SettingsStyle.secondary)
                                .padding(.top, 18).accessibilityElement(children: .combine)
                        }
                    } else {
                        habitHeader
                        if draft.filePlan?.operation == .move { destinationPicker }
                        if !sample.isEmpty { preview }
                        else if busy { loadingState }
                        else {
                            Text("Describe a change below to generate a fresh example.")
                                .font(SettingsStyle.font(12)).foregroundStyle(SettingsStyle.secondary)
                        }
                        details
                    }
                }.padding(.horizontal, 24).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 12) {
                if let question {
                    Label(question, systemImage: "questionmark.circle")
                        .font(SettingsStyle.font(13)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(SettingsStyle.font(12)).foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                composer
                HStack {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(SettingsPill())
                    Spacer()
                    if draft.filePlan?.operation == .move && draft.destinationBookmark == nil && !busy {
                        Text("Choose a folder to save").font(SettingsStyle.font(11)).foregroundStyle(SettingsStyle.secondary)
                    }
                    Button(original.isSyncable ? "Save changes" : "Create habit") { confirm() }
                        .keyboardShortcut("s", modifiers: .command).buttonStyle(.plain)
                        .font(SettingsStyle.font(12, weight: .medium)).padding(.horizontal, 16).padding(.vertical, 9)
                        .foregroundStyle(canConfirm ? Color(white: 0.095) : .white.opacity(0.35))
                        .background(canConfirm ? Color.white.opacity(0.92) : Color.white.opacity(0.06), in: Capsule())
                        .disabled(!canConfirm)
                }
            }.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 20)
        }.frame(width: 520, height: 570).font(SettingsStyle.font()).foregroundStyle(.white.opacity(0.9))
            .background(SettingsStyle.background).preferredColorScheme(.dark).tint(.white)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: result != nil)
            .task(id: run) {
                guard run > 0 else { return }
                defer { busy = false }
                let owner = AccountStore.shared.user?.id
                do {
                    guard let credential = await GatewayAccess.credential() else { throw CorrectionClient.Failure.unavailable }
                    guard owner == AccountStore.shared.user?.id else { return }
                    if !testingOnly {
                        let design = try await CorrectionClient().designHabit(submitted, current: !draft.instruction.isEmpty ? draft : nil, requestID: UUID(), credential: credential)
                        try Task.checkCancellation()
                        guard owner == AccountStore.shared.user?.id else { return }
                        if let clarification = design.question { question = clarification; previousRequest = submitted; query = ""; return }
                        if draft.filePlan?.operation != design.filePlan?.operation { draft.destinationBookmark = nil; destinationName = "" }
                        draft.filePlan = design.filePlan; fileSamples = design.fileSamples ?? []
                        draft.name = customName ?? design.name; draft.instruction = design.instruction; draft.summary = design.summary; draft.output = .replace
                        question = nil; previousRequest = ""; sample = design.filePlan == nil ? design.sample : fileSamples.map(\.name).joined(separator: "\n"); showsInput = false; result = nil
                    }
                    if let plan = draft.filePlan {
                        progress = plan.operation == .move ? "Testing a move on example files…" : "Trying your naming rules…"
                        result = try await testFiles(plan, credential: credential)
                        try Task.checkCancellation()
                        guard owner == AccountStore.shared.user?.id else { result = nil; return }
                        query = ""
                        return
                    }
                    progress = "Trying your action…"
                    let answer = try await CorrectionClient().reading(sample, action: "text_habit", requestID: UUID(), credential: credential, update: { _ in }, refinement: draft.instruction)
                    try Task.checkCancellation()
                    guard owner == AccountStore.shared.user?.id else { return }
                    result = answer; query = ""
                } catch {
                    guard !Task.isCancelled else { return }
                    self.error = error.localizedDescription
                }
            }
    }
    private var habitHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button { showsIcons.toggle() } label: {
                    Image(systemName: draft.resolvedIconName)
                        .symbolRenderingMode(.monochrome).font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white).frame(width: 40, height: 40)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain).disabled(busy)
                .accessibilityLabel("Change icon").help("Change icon")
                .popover(isPresented: $showsIcons) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Choose an icon").font(.headline)
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 6), count: 6), spacing: 6) {
                            ForEach(TextHabit.iconChoices, id: \.symbol) { choice in
                                Button {
                                    draft.iconName = choice.symbol
                                    showsIcons = false
                                } label: {
                                    Image(systemName: choice.symbol).symbolRenderingMode(.monochrome)
                                        .font(.system(size: 16, weight: .medium))
                                        .frame(width: 36, height: 36)
                                        .background(.white.opacity(draft.resolvedIconName == choice.symbol ? 0.16 : 0.04), in: RoundedRectangle(cornerRadius: 8))
                                }.buttonStyle(.plain).accessibilityLabel(choice.label).help(choice.label)
                                    .accessibilityAddTraits(draft.resolvedIconName == choice.symbol ? .isSelected : [])
                            }
                        }
                        Button("Use automatic icon") { draft.iconName = nil; showsIcons = false }
                            .buttonStyle(.plain).font(.callout).foregroundStyle(.secondary)
                    }.padding(16).foregroundStyle(.white).preferredColorScheme(.dark)
                }
                TextField("Name your habit", text: $draft.name)
                    .textFieldStyle(.plain).font(SettingsStyle.font(18, weight: .semibold))
                    .accessibilityLabel("Habit name").focused($nameFocused).disabled(busy)
                    .onChange(of: draft.name) { _, value in if nameFocused { customName = value } }
                Button("Rename habit", systemImage: "pencil") { nameFocused = true }
                    .labelStyle(.iconOnly).buttonStyle(TeroQuietButtonStyle()).frame(width: 32, height: 32)
                    .help("Edit the habit name").disabled(busy)
            }
            Text(draft.rankingDescription).font(SettingsStyle.font(13)).foregroundStyle(SettingsStyle.secondary)
                .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            if draft.name.count > 40 || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Choose a name between 1 and 40 characters.").font(SettingsStyle.font(11)).foregroundStyle(SettingsStyle.secondary)
            }
        }
    }
    private var details: some View {
            DisclosureGroup("Instructions & rules") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(draft.instruction).textSelection(.enabled)
                    if let plan = draft.filePlan {
                        Text((plan.extensions.isEmpty ? "All regular files" : plan.extensions.map { $0.uppercased() }.joined(separator: ", ") + " files")
                            + (plan.nameContains.isEmpty ? "" : " · Name contains " + plan.nameContains.joined(separator: " or ")))
                        if plan.usesContents == true { Text("Reads selected file contents to suggest names.") }
                    }
                }.font(SettingsStyle.font(12)).lineSpacing(4).padding(.top, 8)
            }.font(SettingsStyle.font(11)).foregroundStyle(SettingsStyle.secondary)
    }
    private var destinationPicker: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder").font(.system(size: 18)).foregroundStyle(.orange).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Destination").font(SettingsStyle.font(12, weight: .medium))
                Text(destinationName.isEmpty ? "Choose where this habit moves your files." : destinationName)
                    .font(SettingsStyle.font(12)).foregroundStyle(SettingsStyle.secondary).lineLimit(2)
            }
            Spacer()
            Button(destinationName.isEmpty ? "Choose folder…" : "Change…", action: pickDestination)
                .buttonStyle(SettingsPill()).disabled(busy)
        }.padding(12).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(question != nil ? "Your answer" : draft.instruction.isEmpty ? "What would you like to do?" : "Tell Tero what to change")
                    .font(SettingsStyle.font(12, weight: .medium))
                Spacer()
                if busy { ReadingActivityGlyph().frame(width: 16, height: 16).accessibilityLabel(progress) }
            }
            AskPromptEditor(query: query, update: { query = $0 }, submit: submit, enabled: !busy,
                accessibilityLabel: question != nil ? "Clarification answer" : draft.instruction.isEmpty ? "Describe your habit" : "Describe changes to your habit")
                .frame(height: 56)
                .overlay(alignment: .topLeading) {
                    if query.isEmpty {
                        Text(question != nil ? "Your answer…" : draft.instruction.isEmpty ? "Move my selected files to a folder…" : "Make it shorter, translate to English, add a rule…")
                            .font(SettingsStyle.font(14)).foregroundStyle(.white.opacity(0.4)).allowsHitTesting(false)
                    }
                }
            HStack(spacing: 10) {
                Text(busy ? progress : "Return to send · Shift Return for a new line")
                    .font(SettingsStyle.font(11)).foregroundStyle(SettingsStyle.secondary).lineLimit(1)
                Spacer()
                Button("Send request", systemImage: "arrow.up", action: submit)
                    .labelStyle(.iconOnly).font(.system(size: 13, weight: .semibold)).frame(width: 32, height: 32)
                    .buttonStyle(TeroQuietButtonStyle()).help("Send request. Creation and tests use your AI provider.")
                    .disabled(busy || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(14).background { TeroReadingSurface(cornerRadius: 12) }
    }
    private var loadingState: some View {
        HStack(spacing: 12) {
            ReadingActivityGlyph().scaleEffect(1.5).frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 5) {
                ActivityLabel(title: progress).font(SettingsStyle.font(13, weight: .medium))
                Text("Your request stays below while Tero works.").font(SettingsStyle.font(12)).foregroundStyle(SettingsStyle.secondary)
            }
        }.padding(.vertical, 18).accessibilityElement(children: .combine)
    }
    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("Example").font(SettingsStyle.font(12, weight: .medium))
                Spacer()
                Picker("Preview", selection: $showsInput) {
                    Text("Before").tag(true); Text("After").tag(false)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 132)
                Button("Test again", systemImage: "arrow.clockwise") { testingOnly = true; beginRun() }
                    .labelStyle(.iconOnly).frame(width: 32, height: 32)
                    .keyboardShortcut("t", modifiers: .command).buttonStyle(TeroQuietButtonStyle())
                    .help("Test again. Uses your AI provider.")
                    .disabled(busy || draft.instruction.isEmpty || (draft.filePlan != nil && fileSamples.isEmpty))
            }
            if busy && !showsInput { loadingState }
            else {
                ScrollView {
                Text(showsInput ? sample : result ?? "Describe a change below to try this habit.")
                    .font(SettingsStyle.font(13)).lineSpacing(5).textSelection(.enabled)
                    .foregroundStyle(!showsInput && result == nil ? SettingsStyle.secondary : .white.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }.frame(height: draft.filePlan?.operation == .move ? 60 : 90)
                    .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
    private func pickDestination() {
        let picker = NSOpenPanel(); picker.canChooseDirectories = true; picker.canChooseFiles = false
        picker.allowsMultipleSelection = false; picker.prompt = "Choose destination"
        guard picker.runModal() == .OK, let url = picker.url else { return }
        do {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw LocalFileIO.Failure.unavailable }
            draft.destinationBookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            destinationName = url.lastPathComponent; error = nil
        } catch { self.error = "Could not keep this folder. Choose another destination." }
    }
    private func testFiles(_ plan: FileHabitPlan, credential: String) async throws -> String {
        guard FileHabitSample.valid(fileSamples, plan: plan) else { throw CorrectionClient.Failure.invalid }
        let workspace = try LocalFileIO.workspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let source = workspace.appendingPathComponent("source"), target = workspace.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let urls = fileSamples.map { source.appendingPathComponent($0.name) }
        for (sample, url) in zip(fileSamples, urls) { try Data(sample.content.utf8).write(to: url) }
        let snapshots = try urls.map { try LocalFileIO.Snapshot($0) }
        let outputs: [URL]
        if plan.operation == .rename {
            let inputs = fileSamples.enumerated().map {
                FileNamingInput(id: "file-\($0.offset)", text: plan.usesContents == true ? $0.element.content : "Original filename: " + $0.element.name, file: nil, name: $0.element.name)
            }
            let names = try await CorrectionClient().renameFiles(inputs, requestID: UUID(), credential: credential, refinement: draft.instruction)
            outputs = try FileNameProposal.targets(urls, stems: names, format: false)
        } else { outputs = urls.map { target.appendingPathComponent($0.lastPathComponent) } }
        _ = try await FileWorkflowEngine().relocate(urls, targets: outputs, snapshots: snapshots)
        return zip(fileSamples, outputs).map { sample, output in
            sample.name + " → " + (plan.operation == .move ? (destinationName.isEmpty ? "Chosen folder" : destinationName) + "/" : output.lastPathComponent)
        }.joined(separator: "\n\n")
    }
    private func submit() {
        guard !busy else { return }
        let request = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if request.isEmpty { if canConfirm { confirm() }; return }
        submitted = question == nil ? request : previousRequest + "\n" + request
        testingOnly = false; beginRun()
    }
    private func beginRun() { error = nil; busy = true; progress = testingOnly ? "Trying your action…" : "Shaping your action…"; run += 1 }
    private var canConfirm: Bool {
        draft.isValid && !draft.needsDestination && !busy && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && question == nil && !store.loadFailed
            && (result != nil || (original.isSyncable && draft.instruction == original.instruction && draft.filePlan == original.filePlan))
    }
    private func confirm() { guard canConfirm else { return }; if store.save(draft) { dismiss() } else { error = store.error } }
}
