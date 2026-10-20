import Foundation
import ImageIO
import UniformTypeIdentifiers
import PDFKit

/// Temporary provider payload. Never contains a path or original filename.
struct FileSummaryInput: Encodable, Sendable {
  let mime: String
  let data: String
}

actor FileSummaryReader {
  enum Failure: Error, LocalizedError {
    case unsupported, tooLarge, locked
    var errorDescription: String? {
      switch self {
      case .unsupported: "Choose one image, PDF, DOCX, XLSX, PPTX or UTF-8 text file."
      case .tooLarge: "Use a PDF under 4 MB and 30 pages, office text under 1 MB fitting in 30 pages, or an image under 40 MP and 100 MB."
      case .locked: "Unlock this PDF before summarizing it."
      }
    }
  }
  static func accepts(_ files: [InvocationContext.FileObservation]) -> Bool {
    guard files.count == 1, let file = files.first, file.url.isFileURL,
          file.metadataAvailable, file.isDirectory == false, file.isSymbolicLink == false,
          let type = file.typeIdentifier.flatMap(UTType.init) else { return false }
    return type.conforms(to: .pdf) || [UTType.png, .jpeg, .heic, .tiff, .bmp].contains { type.conforms(to: $0) }
      || DocumentFamily(file.url) != nil
  }
  func prepare(_ url: URL) async throws -> FileSummaryInput {
    if let family = DocumentFamily(url), family != .pdf {
      let workspace = try LocalFileIO.workspace()
      defer { try? FileManager.default.removeItem(at: workspace) }
      let snapshot = try LocalFileIO.Snapshot(url)
      let text = try await OfficeDocumentText.read(url, workspace: workspace)
      let converted = workspace.appendingPathComponent("document.pdf")
      try TextPDF.write("Extracted text only. Embedded images, charts and original layout are not included.\n\n" + text, to: converted, maxPages: 30)
      guard try LocalFileIO.Snapshot(url) == snapshot else { throw LocalFileIO.Failure.changed }
      return try await prepare(converted)
    }
    try Task.checkCancellation()
    guard Self.accepts([.read(url)]) else { throw Failure.unsupported }
    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
      .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true else { throw Failure.unsupported }
    guard values.isUbiquitousItem != true || values.ubiquitousItemDownloadingStatus == .current
      || values.ubiquitousItemDownloadingStatus == .downloaded else { throw Failure.unsupported }
    let isPDF = UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true
    guard let size = values.fileSize, size > 0, size <= (isPDF ? 4_000_000 : 100_000_000) else { throw Failure.tooLarge }
    let bytes: Data
    let mime: String
    if isPDF {
      bytes = try Data(contentsOf: url)
      guard bytes.count <= 4_000_000, bytes.starts(with: Data("%PDF-".utf8)),
            let document = PDFDocument(data: bytes) else { throw Failure.unsupported }
      guard !document.isLocked else { throw Failure.locked }
      guard document.pageCount > 0, document.pageCount <= 30 else { throw Failure.tooLarge }
      mime = "application/pdf"
    } else {
      guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) == 1,
            let info = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = info[kCGImagePropertyPixelWidth] as? Int,
            let height = info[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0, width <= 40_000_000 / height else { throw Failure.tooLarge }
      guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: 2048
      ] as CFDictionary), let space = CGColorSpace(name: CGColorSpace.sRGB),
            let canvas = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
              bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw Failure.unsupported }
      canvas.setFillColor(CGColor(gray: 1, alpha: 1))
      canvas.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
      canvas.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
      guard let rendered = canvas.makeImage() else { throw Failure.unsupported }
      let output = NSMutableData()
      guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { throw Failure.unsupported }
      CGImageDestinationAddImage(destination, rendered, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
      guard CGImageDestinationFinalize(destination), output.length <= 4_000_000 else { throw Failure.tooLarge }
      bytes = output as Data
      mime = "image/jpeg"
    }
    try Task.checkCancellation()
    return FileSummaryInput(mime: mime, data: bytes.base64EncodedString())
  }
}


/// Opaque identifiers bind each proposal to its original file; paths stay on the Mac.
struct FileNamingInput: Encodable, Sendable {
  let id: String
  let text: String?
  let file: FileSummaryInput?
  var name: String? = nil
}
struct FileNameProposal: Codable, Sendable, Equatable {
  let id: String
  let stem: String
  static func ordered(_ proposals: [Self], count: Int, format: Bool = true) throws -> [String] {
    let ids = (0..<count).map { "file-\($0)" }
    guard proposals.count == count, Set(proposals.map(\.id)) == Set(ids),
      proposals.allSatisfy({ FileWorkflowEngine.validStem($0.stem) && $0.stem == $0.stem.trimmingCharacters(in: .whitespacesAndNewlines) }) else {
      throw LocalFileIO.Failure.conversionFailed
    }
    let names = Dictionary(uniqueKeysWithValues: proposals.map { ($0.id, $0.stem) })
    let ordered = ids.map { format ? formatted(names[$0]!) : names[$0]! }
    guard ordered.allSatisfy(FileWorkflowEngine.validStem) else { throw FileWorkflowEngine.Failure.invalidName }
    return ordered
  }
  /// One deterministic naming style for AI proposals and manual edits.
  static func formatted(_ stem: String) -> String {
    let words = stem.split { $0.isWhitespace || $0 == "-" || $0 == "_" }.map(String.init)
    guard let first = words.first else { return "" }
    if words.count >= 4 || words.joined().count > 32 {
      return words.map { $0.lowercased() }.joined(separator: "-")
    }
    if words.count == 1 {
      return first == first.uppercased() ? first.lowercased() : first.prefix(1).lowercased() + first.dropFirst()
    }
    return first.lowercased() + words.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined()
  }
  static func targets(_ urls: [URL], stems: [String], format: Bool = true) throws -> [URL] {
    guard urls.count == stems.count, stems.allSatisfy(FileWorkflowEngine.validStem) else { throw FileWorkflowEngine.Failure.invalidName }
    let formattedStems = zip(urls, stems).map { url, proposal in
      guard !format else { return formatted(proposal) }
      // Personal rules preserve the extension; tolerate a model returning the full basename.
      let suffix = "." + url.pathExtension
      return !url.pathExtension.isEmpty && proposal.lowercased().hasSuffix(suffix.lowercased())
        ? String(proposal.dropLast(suffix.count)) : proposal
    }
    guard formattedStems.allSatisfy(FileWorkflowEngine.validStem) else { throw FileWorkflowEngine.Failure.invalidName }
    return zip(urls, formattedStems).map { url, stem in
      url.deletingLastPathComponent().appendingPathComponent(stem + (url.pathExtension.isEmpty ? "" : "." + url.pathExtension))
    }
  }
}
extension FileSummaryReader {
  func namingInputs(_ urls: [URL], snapshots: [LocalFileIO.Snapshot]) async throws -> [FileNamingInput] {
    guard !urls.isEmpty, urls.count <= 20, snapshots.count == urls.count else { throw LocalFileIO.Failure.unavailable }
    var inputs: [FileNamingInput] = []; var bytes = 0
    for (index, url) in urls.enumerated() {
      try Task.checkCancellation()
      guard try LocalFileIO.Snapshot(url) == snapshots[index] else { throw LocalFileIO.Failure.changed }
      let input: FileNamingInput
      if ["txt", "md", "csv", "tsv", "json", "yaml", "yml", "log", "swift", "js", "ts", "py", "html", "css"].contains(url.pathExtension.lowercased()) {
        guard snapshots[index].bytes <= 120_000 else { throw Failure.tooLarge }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.unsupported }
        bytes += data.count; input = .init(id: "file-\(index)", text: text, file: nil)
      } else {
        let file = try await prepare(url)
        bytes += Data(base64Encoded: file.data)?.count ?? 4_000_001
        input = .init(id: "file-\(index)", text: nil, file: file)
      }
      guard bytes <= 4_000_000 else { throw Failure.tooLarge }
      guard try LocalFileIO.Snapshot(url) == snapshots[index] else { throw LocalFileIO.Failure.changed }
      inputs.append(input)
    }
    return inputs
  }
}
