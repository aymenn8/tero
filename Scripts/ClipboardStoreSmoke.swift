import AppKit

@main struct ClipboardStoreSmoke {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "tero-clipboard-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let board = NSPasteboard.withUniqueName()
        defer {
            board.releaseGlobally()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let url = root.appendingPathComponent("history.json")
        board.setString("preexisting", forType: .string)
        let store = ClipboardStore(url: url, defaults: defaults, pasteboard: board)
        store.poll()
        precondition(store.history.entries.isEmpty)
        board.clearContents(); board.setString("synthetic first", forType: .string)
        store.poll()
        precondition(store.history.entries.map(\.text) == ["synthetic first"])
        let reloaded = ClipboardStore(url: url, defaults: defaults, pasteboard: board)
        precondition(reloaded.history.entries == store.history.entries)
        let savedEntry = store.history.entries[0]
        precondition(store.togglePin(savedEntry))
        let pinnedReload = ClipboardStore(url: url, defaults: defaults, pasteboard: board)
        precondition(pinnedReload.history.entries.first?.isPinned == true)
        precondition(store.togglePin(store.history.entries[0]))
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        precondition((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        board.clearContents(); board.setString("synthetic secret", forType: .string)
        board.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        store.poll()
        precondition(store.history.entries.count == 1)
        store.setEnabled(false)
        board.clearContents(); board.setString("paused content", forType: .string)
        store.poll(); store.setEnabled(true); store.poll()
        precondition(store.history.entries.count == 1)
        store.browsing = true
        board.clearContents(); board.setString("deferred content", forType: .string)
        store.poll(); precondition(store.history.entries.count == 1)
        store.browsing = false; store.poll()
        precondition(store.history.entries.count == 2)
        precondition(store.copy("own copy"))
        store.poll(); precondition(store.history.entries.count == 2)
        let fixture = root.appendingPathComponent("sample.txt")
        try Data("sample file".utf8).write(to: fixture)
        board.clearContents(); board.writeObjects([fixture as NSURL])
        store.poll()
        let fileEntry = store.history.entries[0]
        precondition(fileEntry.kind == .files && fileEntry.files?.first?.name == "sample.txt")
        precondition(store.copy(fileEntry))
        precondition(ClipboardCapture.resolvedFiles(fileEntry)?.map { $0.resolvingSymlinksInPath() } == [fixture.resolvingSymlinksInPath()])
        try FileManager.default.removeItem(at: fixture)
        precondition(!store.copy(fileEntry))
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.bitmapData?.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        let png = bitmap.representation(using: .png, properties: [:])!
        board.clearContents(); board.setData(png, forType: .png)
        store.poll()
        let imageEntry = store.history.entries[0]
        precondition(imageEntry.kind == .image && imageEntry.pixelWidth == 2)
        precondition(store.copy(imageEntry) && board.data(forType: .png) != nil)
        board.clearContents(); board.setString("https://example.com", forType: .string)
        store.poll()
        precondition(store.history.entries[0].kind == .link)
        let multimedia = ClipboardStore(url: url, defaults: defaults, pasteboard: board)
        precondition(multimedia.history.entries.contains { $0.kind == .image })
        precondition(multimedia.history.entries.contains { $0.kind == .files })
        _ = store.copy("own copy")
        store.clear(); store.poll()
        precondition(store.history.entries.isEmpty)
        precondition(board.string(forType: .string) == "own copy")
        precondition(!FileManager.default.fileExists(atPath: url.path))
        print("PASS: isolated clipboard capture, persistence, permissions, confidential exclusion, pause/resume, stable browsing, self-copy, files/images/links, missing files, migration and clear")
    }
}
