import Foundation
import UniformTypeIdentifiers

/// Local ephemeral observations, not a permission grant or a serialized analytics payload.
struct InvocationContext: Equatable, Sendable {
    enum Surface: String, Sendable { case writing, reading, unknown }
    enum Capture: String, Sendable { case unavailable, protectedField, partial, observed }
    let capturedAt: Date
    let applicationID: String?
    var applicationName: String?
    enum Limitation: String, Hashable, Sendable {
        case readBudgetReached, ancestorLimitReached, roleUnavailable
        case windowUnavailable, webLocationUnavailable, excerptUnavailable
    }
    enum FileCapture: String, Sendable {
        case observed, partial, permissionRequired, unavailable, tooMany, selectionChanged
    }
    enum FileOrigin: Equatable, Sendable { case finder, clipboardFiles(UUID), clipboardImage(UUID) }
    var fileOrigin: FileOrigin = .finder
    var hasActionableFiles: Bool {
        if fileOrigin == .finder { return applicationID == "com.apple.finder" }
        return true
    }
    var isClipboardImage: Bool { if case .clipboardImage = fileOrigin { return true }; return false }
    var fileCapture: FileCapture?
    var files: [FileObservation] = []
    struct FileObservation: Equatable, Sendable {
        let url: URL
        var name: String { url.lastPathComponent }
        var extensionName: String { url.pathExtension }
        var parentPath: String { url.deletingLastPathComponent().path }
        var typeIdentifier: String?
        var byteCount: Int?
        var isDirectory: Bool?
        var isSymbolicLink: Bool?
        var metadataAvailable = false

        static func read(_ url: URL, includeMetadata: Bool = true) -> Self {
            var item = Self(url: url)
            guard includeMetadata, url.isFileURL,
                  let values = try? url.resourceValues(forKeys: [
                    .contentTypeKey, .fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey
                  ]) else { return item }
            item.typeIdentifier = values.contentType?.identifier
            item.isDirectory = values.isDirectory
            item.isSymbolicLink = values.isSymbolicLink
            // A folder's own directory entry size is not its contents' size.
            item.byteCount = values.isDirectory == false ? values.fileSize : nil
            item.metadataAvailable = true
            return item
        }
    }
    var capture: Capture = .unavailable
    var limitations: Set<Limitation> = []
    var windowTitle: String?
    var elementRole: String?
    var elementSubrole: String?
    var elementLabel: String?
    var elementDescription: String?
    var elementPlaceholder: String?
    /// Nearest ancestors first; observed accessibility labels, never inferred page sections.
    var containers: [Container] = []
    struct Container: Equatable, Sendable {
        let role: String
        let label: String?
    }
    enum Attribute: Hashable { case role, subrole, title, description, placeholder, url }
    var surface: Surface = .unknown
    /// Only a host observed on an ancestor AXWebArea. No queries, fragments or URL paths retained.
    var webHost: String?
    /// AXStringForRange response, limited to this same focused element; never the whole page.
    var nearbyText: String?

    static func surface(role: String?, editable: Bool) -> Surface {
        if editable { return .writing }
        // Non-settable AXValue is NOT proof that a web composer is read-only.
        return role == "AXStaticText" ? .reading : .unknown
    }

    static func host(from raw: String) -> String? {
        guard raw.utf8.count <= 8192, let parts = URLComponents(string: raw),
              ["https", "http"].contains(parts.scheme?.lowercased() ?? ""),
              parts.user == nil, parts.password == nil, let host = parts.host, !host.isEmpty else { return nil }
        return host.lowercased()
    }

    static func excerptRange(selection: NSRange, total: Int) -> NSRange? {
        guard total >= 0, selection.location >= 0, selection.length >= 0,
              selection.location <= total, selection.length <= total - selection.location else { return nil }
        let start = max(0, selection.location - 240)
        let wanted = min(960, min(selection.length, 480) + 480)
        return NSRange(location: start, length: min(wanted, total - start))
    }
}
