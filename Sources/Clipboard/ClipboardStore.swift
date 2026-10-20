import AppKit
import Carbon
import Observation

@MainActor @Observable
final class ClipboardStore {
    private(set) var history = ClipboardHistory()
    private(set) var enabled: Bool
    private(set) var error: String?
    private let url: URL
    private let defaults: UserDefaults
    private let pasteboard: NSPasteboard
    private var lastChange: Int
    private var timer: Task<Void, Never>?
    var browsing = false

    init(url: URL, defaults: UserDefaults = .standard, pasteboard: NSPasteboard = .general) {
        self.url = url
        self.defaults = defaults
        self.pasteboard = pasteboard
        self.lastChange = pasteboard.changeCount // Do not import pre-existing clipboard contents.
        enabled = defaults.object(forKey: "clipboardHistoryEnabled") as? Bool ?? true
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 50_000_000 else { throw CocoaError(.fileReadCorruptFile) }
                history = try JSONDecoder().decode(ClipboardHistory.self, from: Data(contentsOf: url))
                history.prune()
                persist()
            } catch {
                enabled = false
                self.error = "History could not be loaded. Clear it to start again."
            }
        }
    }

    static func live() -> ClipboardStore {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.aymenkadri.tero.dev")
        return ClipboardStore(url: folder.appendingPathComponent("Clipboard").appendingPathComponent("history-v1.json"))
    }

    func start() {
        guard timer == nil else { return }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                self?.poll()
            }
        }
    }

    func stop() { timer?.cancel(); timer = nil }

    func poll() {
        guard !browsing else { return } // Keep the visible list stable while the user chooses.
        if history.entries.contains(where: { !$0.isPinned && Date().timeIntervalSince($0.copiedAt) >= ClipboardHistory.retention }) {
            refreshRetention()
        }
        let change = pasteboard.changeCount
        guard change != lastChange else { return }
        lastChange = change
        guard enabled, error == nil,
              ClipboardHistory.accepts(types: Set((pasteboard.types ?? []).map(\.rawValue)),
                                       secureInput: IsSecureEventInputEnabled()),
              let entry = ClipboardCapture.read(pasteboard, source: NSWorkspace.shared.frontmostApplication),
              pasteboard.changeCount == change else { return }
        history.record(entry)
        persist()
    }

    func setEnabled(_ value: Bool) {
        guard error == nil else { return }
        lastChange = pasteboard.changeCount
        enabled = value
        defaults.set(value, forKey: "clipboardHistoryEnabled")
    }

    func clear() {
        // Clear history only; leave the system clipboard untouched.
        do {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            history = ClipboardHistory()
            lastChange = pasteboard.changeCount
            error = nil
        } catch { self.error = "History could not be cleared. Try again." }
    }

    @discardableResult func togglePin(_ entry: ClipboardEntry) -> Bool {
        guard history.setPinned(!entry.isPinned, id: entry.id) else { return false }
        persist()
        return error == nil
    }

    func remove(_ entry: ClipboardEntry) {
        history.entries.removeAll { $0.id == entry.id }
        persist()
    }

    func copy(_ text: String) -> Bool {
        pasteboard.clearContents()
        let copied = pasteboard.setString(text, forType: .string)
        lastChange = pasteboard.changeCount
        return copied
    }

    func copy(_ entry: ClipboardEntry) -> Bool {
        if entry.kind == .text || entry.kind == .link { return copy(entry.text) }
        let files = entry.kind == .files ? ClipboardCapture.resolvedFiles(entry) : nil
        guard entry.kind == .image ? entry.imageData != nil : files != nil else { return false }
        pasteboard.clearContents()
        let copied: Bool
        if let data = entry.imageData { copied = pasteboard.setData(data, forType: .png) }
        else { copied = pasteboard.writeObjects((files ?? []).map { $0 as NSURL }) }
        lastChange = pasteboard.changeCount
        return copied
    }

    func refreshRetention() { history.prune(); if error == nil { persist() } }

    private func persist() {
        do {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(history)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            enabled = false
            self.error = "History could not be saved. Recording is paused."
        }
    }
}
