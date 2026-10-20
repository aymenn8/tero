import AppKit
import UniformTypeIdentifiers

/// The fixed script reads only Finder's explicit selection. No interpolated user input.
actor FinderSelectionReader {
    enum Failure: Error { case permission, unavailable, tooMany }

    func capture() throws -> [URL] {
        guard !Task.isCancelled else { throw CancellationError() }
        let script = NSAppleScript(source: """
        with timeout of 5 seconds
            tell application "Finder"
                set chosenItems to selection
                if (count of chosenItems) > 100 then error "Too many items" number 9001
                set selectedPaths to {}
                repeat with chosenItem in chosenItems
                    set end of selectedPaths to POSIX path of (chosenItem as alias)
                end repeat
                return selectedPaths
            end tell
        end timeout
        """)
        var error: NSDictionary?
        guard let result = script?.executeAndReturnError(&error), error == nil else {
            let code = error?[NSAppleScript.errorNumber] as? Int
            if code == -1743 { throw Failure.permission }
            if code == 9001 { throw Failure.tooMany }
            throw Failure.unavailable
        }
        guard !Task.isCancelled else { throw CancellationError() }
        guard result.numberOfItems > 0 else { return [] }
        return try (1...result.numberOfItems).map { index in
            guard let path = result.atIndex(index)?.stringValue, path.hasPrefix("/") else {
                throw Failure.unavailable
            }
            return URL(fileURLWithPath: path).standardizedFileURL
        }
    }

    /// Read-only generic snapshot. Never enumerates folders or opens file contents.
    func captureContext(base: InvocationContext) throws -> InvocationContext {
        var context = base
        let urls: [URL]
        do {
            urls = try capture()
        } catch Failure.permission {
            context.fileCapture = .permissionRequired
            return context
        } catch Failure.tooMany {
            context.fileCapture = .tooMany
            return context
        } catch is CancellationError { throw CancellationError() }
        catch {
            context.fileCapture = .unavailable
            return context
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.35
        for url in urls {
            try Task.checkCancellation()
            context.files.append(.read(url, includeMetadata: ProcessInfo.processInfo.systemUptime < deadline))
        }
        // File metadata may take time on remote volumes; reject a changed selection.
        do {
            guard Set(try capture()) == Set(urls) else {
                context.files = []
                context.fileCapture = .selectionChanged
                return context
            }
        } catch is CancellationError { throw CancellationError() }
        catch {
            context.files = []
            context.fileCapture = .unavailable
            return context
        }
        let complete = context.files.allSatisfy(\.metadataAvailable)
        context.fileCapture = complete ? .observed : .partial
        context.capture = complete ? .observed : .partial
        return context
    }

    func allAudio(_ urls: [URL]) -> Bool {
        !urls.isEmpty && urls.allSatisfy { url in
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentTypeKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true else { return false }
            return values.contentType?.conforms(to: .audio) == true
                || UTType(filenameExtension: url.pathExtension)?.conforms(to: .audio) == true
        }
    }
}


extension FinderSelectionReader {
  /// History references are an explicit selection, independently of the active Finder window.
  func validates(_ context: InvocationContext) async throws -> Bool {
    guard context.hasActionableFiles, !context.files.isEmpty else { return false }
    if context.fileOrigin == .finder { return Set(try capture()) == Set(context.files.map(\.url)) }
    return context.files.allSatisfy { (try? LocalFileIO.Snapshot($0.url)) != nil }
  }
}
