import Foundation
import CryptoKit

struct ClipboardEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    let text: String
    let copiedAt: Date
    var contentKind: ClipboardKind?
    var sourceName: String?
    var sourceBundleID: String?
    var copies: Int?
    var pinned: Bool?
    var isPinned: Bool { pinned == true }
    var imageData: Data?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var files: [ClipboardFile]?

    var kind: ClipboardKind { contentKind ?? (webURL != nil ? .link : .text) }
    var webURL: URL? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.contains(where: \.isWhitespace), let url = URL(string: value),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        return url
    }
    var title: String {
        switch kind {
        case .image: "Image"
        case .files: files?.count == 1 ? files![0].name : "\(files?.count ?? 0) files"
        default: text.replacingOccurrences(of: "\n", with: " ")
        }
    }
    var searchableText: String { [text, sourceName ?? "", sourceBundleID ?? "", kind.rawValue, kind.title,
        files?.map(\.name).joined(separator: " ") ?? ""].joined(separator: " ") }
    func matches(_ query: String) -> Bool {
        let tokens = query.split(whereSeparator: \.isWhitespace)
        let typeText = [kind.rawValue, kind.title, files?.map { $0.url.pathExtension }.joined(separator: " ") ?? ""].joined(separator: " ")
        let appText = [sourceName ?? "", sourceBundleID ?? ""].joined(separator: " ")
        return tokens.allSatisfy { token in
            let value = String(token)
            if value.lowercased().hasPrefix("type:") { return typeText.localizedStandardContains(String(value.dropFirst(5))) }
            if value.lowercased().hasPrefix("app:") { return appText.localizedStandardContains(String(value.dropFirst(4))) }
            return searchableText.localizedStandardContains(value)
        }
    }
    /// Preserve meaningful parameters, raw escaping and fragments. Signed links are left intact.
    var cleanedLink: URL? {
        guard let url = webURL, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let raw = parts.percentEncodedQuery else { return webURL }
        let items = raw.split(separator: "&", omittingEmptySubsequences: false).map(String.init)
        func key(_ item: String) -> String { (item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? "").removingPercentEncoding?.lowercased() ?? "" }
        let keys = items.map(key)
        if keys.contains(where: { $0.hasPrefix("x-amz-") || $0.hasPrefix("x-goog-") || ["signature", "sig", "token", "code", "state"].contains($0) }) { return url }
        let tracking: Set<String> = ["fbclid", "gclid", "dclid", "msclkid", "mc_cid", "mc_eid", "_hsenc", "_hsmi", "igshid", "yclid"]
        let kept = items.filter { !key($0).hasPrefix("utm_") && !tracking.contains(key($0)) }
        guard kept.count != items.count else { return url }
        parts.percentEncodedQuery = kept.isEmpty ? nil : kept.joined(separator: "&")
        return parts.url
    }
    var byteCount: Int { imageData?.count ?? files?.compactMap(\.size).reduce(0, +) ?? text.utf8.count }
    var storageBytes: Int { text.utf8.count + (imageData?.count ?? 0) + (files?.reduce(0) { $0 + ($1.bookmark?.count ?? 0) + $1.url.absoluteString.utf8.count + $1.name.utf8.count } ?? 0) }
    var fingerprint: String {
        let payload = imageData ?? Data((kind == .files ? files?.map { $0.url.absoluteString }.joined(separator: "\n") ?? "" : text).utf8)
        return kind.rawValue + SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    }
    var isValid: Bool {
        switch kind {
        case .text, .link:
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf8.count <= ClipboardHistory.maximumBytes
        case .image:
            imageData != nil && (imageData?.isEmpty == false) && imageData!.count <= ClipboardHistory.maximumImageBytes
        case .files:
            files?.isEmpty == false && files!.count <= 100 && files!.allSatisfy { $0.url.isFileURL }
                && storageBytes <= 2_000_000
        }
    }
}
