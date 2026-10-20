import Foundation
import PDFKit
import Darwin
import CoreText

/// Office and PDF families Tero can read locally (summaries, file naming).
enum DocumentFamily: Sendable {
  case document, spreadsheet, presentation, pdf
  init?(_ url: URL) {
    switch url.pathExtension.lowercased() {
    case "docx", "txt": self = .document
    case "xlsx", "csv", "tsv": self = .spreadsheet
    case "pptx": self = .presentation
    case "pdf": self = .pdf
    default: return nil
    }
  }
}

/// Atomic publication and source fingerprints shared by native file workflows.
enum LocalFileIO {
  enum Failure: Error, LocalizedError {
    case unavailable, changed, conflict, conversionFailed, timeout, lockedPDF, noText, tooLarge
    var errorDescription: String? {
      switch self {
      case .unavailable: "Choose downloaded, regular files."
      case .changed: "Files changed. Select them and open Tero again."
      case .conflict: "An output already exists. Nothing was overwritten."
      case .conversionFailed: "This file couldn't be read. It may be protected or unsupported."
      case .lockedPDF: "Unlock this PDF first."
      case .noText: "This file has no readable text."
      case .timeout: "This took too long. Originals are unchanged."
      case .tooLarge: "Use files under 100 MB and PDFs with at most 300 pages."
      }
    }
  }
  struct Snapshot: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
    let bytes: Int64
    let seconds: Int
    let nanoseconds: Int
    init(_ url: URL) throws {
      var info = stat()
      guard url.isFileURL, lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { throw Failure.unavailable }
      let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
      guard values.isUbiquitousItem != true || values.ubiquitousItemDownloadingStatus == .current || values.ubiquitousItemDownloadingStatus == .downloaded else { throw Failure.unavailable }
      guard info.st_size > 0, info.st_size <= 100_000_000 else { throw Failure.tooLarge }
      device = UInt64(info.st_dev); inode = UInt64(info.st_ino); bytes = info.st_size
      seconds = info.st_mtimespec.tv_sec; nanoseconds = info.st_mtimespec.tv_nsec
    }
  }
  static func workspace() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("tero-files-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    return url
  }
  static func publish(_ staged: URL, to output: URL) throws {
    try Task.checkCancellation()
    // Move an already complete private file to the destination filesystem, then rename
    // exclusively. Finder never sees partially written outputs, even on another volume.
    let temporary = output.deletingLastPathComponent().appendingPathComponent(".tero-" + UUID().uuidString)
    try FileManager.default.copyItem(at: staged, to: temporary)
    defer { try? FileManager.default.removeItem(at: temporary) }
    try Task.checkCancellation()
    guard renamex_np(temporary.path, output.path, UInt32(RENAME_EXCL)) == 0 else {
      throw errno == EEXIST ? Failure.conflict : Failure.conversionFailed
    }
  }
}

enum TextPDF {
  /// Text-only pagination; never silently truncates an office summary.
  static func write(_ text: String, to url: URL, maxPages: Int) throws {
    var box = CGRect(x: 0, y: 0, width: 595, height: 842)
    guard let writer = CGContext(url as CFURL, mediaBox: &box, nil) else { throw LocalFileIO.Failure.conversionFailed }
    defer { writer.closePDF() }
    let font = CTFontCreateWithName("Helvetica" as CFString, 11, nil)
    let value = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
    let framesetter = CTFramesetterCreateWithAttributedString(value)
    let path = CGPath(rect: CGRect(x: 36, y: 36, width: 523, height: 770), transform: nil)
    var offset = 0, pages = 0
    while offset < value.length {
      try Task.checkCancellation()
      pages += 1
      guard pages <= maxPages else {
        if maxPages == 30 { throw FileSummaryReader.Failure.tooLarge }
        throw LocalFileIO.Failure.tooLarge
      }
      let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), path, nil)
      let range = CTFrameGetVisibleStringRange(frame)
      guard range.length > 0 else { throw LocalFileIO.Failure.conversionFailed }
      writer.beginPDFPage(nil); CTFrameDraw(frame, writer); writer.endPDFPage()
      offset += range.length
    }
  }
}

/// Fixed system tools only, no shell, office engine, diagnostics or network fetching.
enum LocalConversionProcess {
  static func run(executable: String, arguments: [String], output: FileHandle? = nil, outputURL: URL? = nil, maxBytes: Int = 4_000_000) async throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = output ?? FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    try await run(process, outputURL: outputURL, maxBytes: maxBytes)
  }
  static func run(_ process: Process, outputURL: URL? = nil, maxBytes: Int = 4_000_000) async throws {
    if process.standardOutput == nil { process.standardOutput = FileHandle.nullDevice }
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    try Task.checkCancellation()
    try process.run()
    let deadline = ContinuousClock.now.advanced(by: .seconds(30))
    do {
      while process.isRunning {
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else { throw LocalFileIO.Failure.timeout }
        if let outputURL {
          let size = try outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
          guard size <= maxBytes else { throw FileSummaryReader.Failure.tooLarge }
        }
        try await Task.sleep(for: .milliseconds(10))
      }
      guard process.terminationStatus == 0 else { throw LocalFileIO.Failure.conversionFailed }
      if let outputURL {
        let size = try outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maxBytes else { throw FileSummaryReader.Failure.tooLarge }
      }
    } catch {
      if process.isRunning { process.terminate() }
      for _ in 0..<20 where process.isRunning { try? await Task.sleep(for: .milliseconds(10)) }
      if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
      process.waitUntilExit()
      throw error
    }
  }
}
