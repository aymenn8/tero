import AppKit
import ImageIO

@MainActor
enum ClipboardCapture {
    static func read(_ board: NSPasteboard, source: NSRunningApplication?) -> ClipboardEntry? {
        var entry = ClipboardEntry(text: "", copiedAt: Date())
        entry.sourceName = source?.localizedName
        entry.sourceBundleID = source?.bundleIdentifier
        if board.types?.contains(.fileURL) == true {
            guard let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
                  !urls.isEmpty, urls.count <= 100 else { return nil }
            entry.contentKind = .files
            entry.files = urls.map { url in
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .nameKey])
                return ClipboardFile(url: url,
                    bookmark: try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil),
                    name: values?.name ?? url.lastPathComponent, size: values?.fileSize)
            }
            return entry
        }
        // File URLs have priority over the icon image supplied by Finder.
        for type in [NSPasteboard.PasteboardType.png, .tiff, NSPasteboard.PasteboardType("public.jpeg")] where board.types?.contains(type) == true {
            guard let data = board.data(forType: type), data.count <= 20_000_000,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 12_000, height <= 12_000,
                  width * height <= 24_000_000,
                  let bitmap = NSBitmapImageRep(data: data),
                  let png = bitmap.representation(using: .png, properties: [:]),
                  png.count <= ClipboardHistory.maximumImageBytes else { return nil }
            entry.contentKind = .image
            entry.imageData = png
            entry.pixelWidth = width; entry.pixelHeight = height
            return entry
        }
        guard let data = board.data(forType: .string) ?? board.data(forType: .URL),
              data.count <= ClipboardHistory.maximumBytes, let text = String(data: data, encoding: .utf8) else { return nil }
        var textEntry = ClipboardEntry(text: text, copiedAt: entry.copiedAt)
        textEntry.sourceName = entry.sourceName
        textEntry.sourceBundleID = entry.sourceBundleID
        return textEntry
    }

    static func resolvedFiles(_ entry: ClipboardEntry) -> [URL]? {
        guard let files = entry.files, !files.isEmpty else { return nil }
        var result: [URL] = []
        for file in files {
            var stale = false
            let resolved = file.bookmark.flatMap {
                try? URL(resolvingBookmarkData: $0, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            } ?? file.url
            guard resolved.isFileURL, FileManager.default.fileExists(atPath: resolved.path) else { return nil }
            result.append(resolved)
        }
        return result
    }
}
