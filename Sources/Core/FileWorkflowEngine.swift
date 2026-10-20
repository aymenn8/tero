import Foundation
import Darwin

enum FileWorkflowKind: String, CaseIterable, Sendable {
  case rename, batchRename, move
  var title: String {
    switch self {
    case .rename: "Rename"
    case .batchRename: "Batch rename"
    case .move: "Move files"
    }
  }
  var searchTerms: [String] {
    switch self {
    case .rename: ["rename", "name", "renommer"]
    case .batchRename: ["batch", "rename", "names", "renommer"]
    case .move: ["move", "folder", "destination", "deplacer"]
    }
  }
  func accepts(_ files: [InvocationContext.FileObservation]) -> Bool {
    guard !files.isEmpty, files.count <= 20, files.allSatisfy({ $0.metadataAvailable && $0.isDirectory == false && $0.isSymbolicLink == false }) else { return false }
    switch self {
    case .rename: return files.count == 1
    case .batchRename: return files.count > 1
    case .move: return true
    }
  }
}

actor FileWorkflowEngine {
  enum Failure: LocalizedError {
    case invalidName, unsupportedArchive, limit, partial(Int)
    var errorDescription: String? {
      switch self {
      case .invalidName: "Use a non-empty filename without slashes or control characters."
      case .unsupportedArchive: "Use a ZIP containing regular files only, without encrypted entries, links or unsafe paths."
      case .limit: "Use up to 20 downloaded files, under 100 MB each."
      case .partial(let count): "Completed \(count) files before an error. Check Finder before retrying."
      }
    }
  }
  static func validStem(_ name: String) -> Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name != "." && name != ".."
      && !name.hasPrefix(".") && name.utf8.count <= 180
      && !name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) || "/:\\".unicodeScalars.contains($0) }
  }
  static func renameTargets(_ urls: [URL], template: String) throws -> [URL] {
    try urls.enumerated().map { index, url in
      let name = template.replacingOccurrences(of: "{original}", with: url.deletingPathExtension().lastPathComponent)
        .replacingOccurrences(of: "{n}", with: String(format: "%02d", index + 1))
      guard validStem(name) else { throw Failure.invalidName }
      return url.deletingLastPathComponent().appendingPathComponent(name).appendingPathExtension(url.pathExtension)
    }
  }
  private func check(_ urls: [URL], snapshots: [LocalFileIO.Snapshot]) throws {
    try Task.checkCancellation()
    guard !urls.isEmpty, urls.count <= 20, urls.count == snapshots.count else { throw LocalFileIO.Failure.changed }
    guard snapshots.reduce(0, { $0 + $1.bytes }) <= 500_000_000 else { throw Failure.limit }
    for (url, snapshot) in zip(urls, snapshots) {
      guard try LocalFileIO.Snapshot(url) == snapshot else { throw LocalFileIO.Failure.changed }
    }
  }
  func relocate(_ urls: [URL], targets: [URL], snapshots: [LocalFileIO.Snapshot]) throws -> [URL] {
    try check(urls, snapshots: snapshots)
    guard urls.count == targets.count, Set(targets.map { $0.path.lowercased() }).count == targets.count else { throw LocalFileIO.Failure.conflict }
    for (source, target) in zip(urls, targets) where source != target {
      guard !FileManager.default.fileExists(atPath: target.path) else { throw LocalFileIO.Failure.conflict }
    }
    var done: [URL] = []
    do {
      for (index, pair) in zip(urls, targets).enumerated() {
        let (source, target) = pair
        try Task.checkCancellation()
        guard try LocalFileIO.Snapshot(source) == snapshots[index] else { throw LocalFileIO.Failure.changed }
        if source != target {
          if renamex_np(source.path, target.path, UInt32(RENAME_EXCL)) != 0 {
            guard errno == EXDEV else { throw errno == EEXIST ? LocalFileIO.Failure.conflict : LocalFileIO.Failure.conversionFailed }
            try LocalFileIO.publish(source, to: target)
            guard try LocalFileIO.Snapshot(source) == snapshots[done.count] else { throw Failure.partial(done.count + 1) }
            do { try FileManager.default.removeItem(at: source) }
            catch { throw Failure.partial(done.count + 1) }
          }
        }
        done.append(target)
      }
    } catch { if !done.isEmpty { throw Failure.partial(done.count) }; throw error }
    return done
  }
}

/// ZIP central-directory validation before invoking the system decoder.
enum SafeZip {
  struct Entry { let name: String; let bytes: Int; let directory: Bool }
  static func entries(_ data: Data, officePackage: Bool = false) throws -> [Entry] {
    func fail() throws -> Never { throw FileWorkflowEngine.Failure.unsupportedArchive }
    func number(_ offset: Int, _ count: Int) throws -> Int {
      guard offset >= 0, offset + count <= data.count else { try fail() }
      return (0..<count).reduce(0) { $0 | Int(data[offset + $1]) << (8 * $1) }
    }
    guard data.count >= 22 else { try fail() }
    var end: Int?
    for index in stride(from: data.count - 22, through: max(0, data.count - 65557), by: -1) {
      if try number(index, 4) == 0x06054b50, index + 22 + (try number(index + 20, 2)) == data.count { end = index; break }
    }
    guard let end, try number(end + 4, 2) == 0, (try number(end + 6, 2)) == 0 else { try fail() }
    let count = try number(end + 10, 2), size = try number(end + 12, 4), start = try number(end + 16, 4)
    guard count > 0, count <= 1000, try number(end + 8, 2) == count, start + size == end else { try fail() }
    var cursor = start, total = 0, names = Set<String>(), entries: [Entry] = []
    for _ in 0..<count {
      guard try number(cursor, 4) == 0x02014b50 else { try fail() }
      let flags = try number(cursor + 8, 2), method = try number(cursor + 10, 2)
      let bytes = try number(cursor + 24, 4), length = try number(cursor + 28, 2)
      let extra = try number(cursor + 30, 2), comment = try number(cursor + 32, 2)
      let mode = try number(cursor + 38, 4) >> 16, local = try number(cursor + 42, 4)
      guard flags & 1 == 0, [0, 8].contains(method), bytes <= 100_000_000,
        cursor + 46 + length + extra + comment <= end,
        let name = String(data: data.subdata(in: cursor + 46..<cursor + 46 + length), encoding: .utf8),
        !name.isEmpty, !name.hasPrefix("/"), !name.hasPrefix("-"), !name.contains("\\"), !name.contains(":"),
        !name.contains("*"), !name.contains("?"), (!name.contains("[") || officePackage && name == "[Content_Types].xml"),
        !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
        !name.split(separator: "/").contains(".."), !name.split(separator: "/").contains("."),
        [0, 0x8000, 0x4000].contains(mode & 0xf000), names.insert(name.lowercased()).inserted else { try fail() }
      guard try number(local, 4) == 0x04034b50, (try number(local + 8, 2)) == method, (try number(local + 6, 2)) == flags else { try fail() }
      let localLength = try number(local + 26, 2), localExtra = try number(local + 28, 2), compressedBytes = try number(cursor + 20, 4)
      guard localLength == length, local + 30 + length + localExtra + compressedBytes <= start,
        data.subdata(in: local + 30..<local + 30 + length) == data.subdata(in: cursor + 46..<cursor + 46 + length) else { try fail() }
      total += bytes; guard total <= 500_000_000 else { try fail() }
      entries.append(.init(name: name, bytes: bytes, directory: name.hasSuffix("/")))
      cursor += 46 + length + extra + comment
    }
    guard cursor == end else { try fail() }
    return entries
  }
}
