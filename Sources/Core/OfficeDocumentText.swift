import Foundation
import PDFKit

/// Bounded local content extraction. No office application, macros or remote relationships.
enum OfficeDocumentText {
  static let maxTextBytes = 1_000_000
  static func read(_ url: URL, workspace: URL) async throws -> String {
    try Task.checkCancellation()
    _ = try LocalFileIO.Snapshot(url)
    let ext = url.pathExtension.lowercased()
    let text: String
    if ext == "pdf" {
      guard let pdf = PDFDocument(url: url) else { throw LocalFileIO.Failure.conversionFailed }
      guard !pdf.isLocked else { throw LocalFileIO.Failure.lockedPDF }
      guard pdf.pageCount <= 300 else { throw LocalFileIO.Failure.tooLarge }
      var pages: [String] = [], bytes = 0
      for index in 0..<pdf.pageCount {
        try Task.checkCancellation()
        let page = pdf.page(at: index)?.string ?? ""
        bytes += page.utf8.count
        guard bytes <= maxTextBytes else { throw FileSummaryReader.Failure.tooLarge }
        pages.append(page)
      }
      text = pages.joined(separator: "\n\n")
    } else if ["txt", "csv", "tsv"].contains(ext) {
      guard let value = String(data: try Data(contentsOf: url), encoding: .utf8) else { throw FileSummaryReader.Failure.unsupported }
      text = value
    } else if ["docx", "xlsx", "pptx"].contains(ext) {
      let package = try Package(url: url, workspace: workspace)
      switch ext {
      case "docx":
        let main = try await package.xml("word/document.xml")
        guard main.name == "document" else { throw FileSummaryReader.Failure.unsupported }
        var parts = [main.prose()]
        for path in package.entries.keys.sorted() where path == "word/footnotes.xml" || path == "word/endnotes.xml" ||
          (path.hasPrefix("word/header") || path.hasPrefix("word/footer")) && path.hasSuffix(".xml") {
          let node = try await package.xml(path)
          parts.append(node.prose())
        }
        text = parts.joined(separator: "\n\n")
      case "pptx":
        let main = try await package.xml("ppt/presentation.xml")
        let relationships = try await package.relationships("ppt/_rels/presentation.xml.rels", base: "ppt")
        var slides: [String] = []
        for (index, slide) in main.descendants("sldId").enumerated() {
          guard let id = slide.relationshipID, let path = relationships[id] else { throw FileSummaryReader.Failure.unsupported }
          let node = try await package.xml(path)
          slides.append("Slide \(index + 1)\n" + node.prose())
        }
        text = slides.joined(separator: "\n\n")
      default:
        let workbook = try await package.xml("xl/workbook.xml")
        let relationships = try await package.relationships("xl/_rels/workbook.xml.rels", base: "xl")
        let strings: [String]
        if package.entries["xl/sharedStrings.xml"] != nil {
          strings = try await package.xml("xl/sharedStrings.xml").descendants("si").map { $0.descendants("t").map(\.text).joined() }
        } else { strings = [] }
        var sheets: [String] = [], hasContent = false
        for sheet in workbook.descendants("sheet") {
          guard let id = sheet.relationshipID, let path = relationships[id] else { throw FileSummaryReader.Failure.unsupported }
          let node = try await package.xml(path)
          var rows: [String] = []
          for row in node.descendants("row") {
            var cells: [String] = []
            for cell in row.children where cell.name == "c" {
              let value = cell.children.first { $0.name == "v" }?.text ?? ""
              let content: String
              switch cell.attributes["t"] {
              case "s":
                guard let index = Int(value), strings.indices.contains(index) else { throw FileSummaryReader.Failure.unsupported }
                content = strings[index]
              case "inlineStr": content = cell.descendants("t").map(\.text).joined()
              case "b": content = value == "1" ? "TRUE" : "FALSE"
              default:
                if value.isEmpty, let formula = cell.children.first(where: { $0.name == "f" }) {
                  content = "=\(formula.text) [saved result unavailable]"
                } else { content = value }
              }
              if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { hasContent = true }
              // Cell addresses preserve sparse columns; saved Excel date serials remain explicit raw values.
              cells.append("\(cell.attributes["r"] ?? "?"): \(content)")
            }
            rows.append(cells.joined(separator: "\t"))
          }
          sheets.append("Sheet: \(sheet.attributes["name"] ?? "Untitled")\n" + rows.joined(separator: "\n"))
        }
        guard hasContent else { throw LocalFileIO.Failure.noText }
        text = "Spreadsheet saved values. Formulas are not recalculated; date/number formatting is not applied.\n\n" + sheets.joined(separator: "\n\n")
      }
    } else { throw FileSummaryReader.Failure.unsupported }
    try Task.checkCancellation()
    guard text.utf8.count <= maxTextBytes else { throw FileSummaryReader.Failure.tooLarge }
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LocalFileIO.Failure.noText }
    return text
  }


  private final class Package {
    let entries: [String: SafeZip.Entry]
    let archive: URL
    let workspace: URL
    var totalBytes = 0
    init(url: URL, workspace: URL) throws {
      let data = try Data(contentsOf: url)
      let entries = try SafeZip.entries(data, officePackage: true)
      self.entries = Dictionary(uniqueKeysWithValues: entries.filter { !$0.directory }.map { ($0.name, $0) })
      self.workspace = workspace
      archive = workspace.appendingPathComponent("source.zip")
      try data.write(to: archive)
    }
    func xml(_ path: String) async throws -> OfficeXMLNode {
      try Task.checkCancellation()
      guard let entry = entries[path], entry.bytes > 0, entry.bytes <= 2_000_000 else { throw FileSummaryReader.Failure.unsupported }
      totalBytes += entry.bytes
      guard totalBytes <= 8_000_000 else { throw FileSummaryReader.Failure.tooLarge }
      let output = workspace.appendingPathComponent(UUID().uuidString + ".xml")
      defer { try? FileManager.default.removeItem(at: output) }
      guard FileManager.default.createFile(atPath: output.path, contents: nil) else { throw LocalFileIO.Failure.conversionFailed }
      let handle = try FileHandle(forWritingTo: output)
      defer { try? handle.close() }
      try await LocalConversionProcess.run(executable: "/usr/bin/unzip", arguments: ["-p", archive.path, path], output: handle, outputURL: output, maxBytes: entry.bytes)
      let data = try Data(contentsOf: output)
      guard data.count == entry.bytes else { throw FileSummaryReader.Failure.unsupported }
      return try OfficeXMLParser.parse(data)
    }
    func relationships(_ path: String, base: String) async throws -> [String: String] {
      let node = try await xml(path)
      var result: [String: String] = [:]
      for rel in node.children where rel.name == "Relationship" && rel.attributes["TargetMode"] != "External" {
        guard let id = rel.attributes["Id"], let target = rel.attributes["Target"],
          !target.contains(":"), !target.contains("\\"), !target.contains("%"), !target.contains("#") else { continue }
        var components = target.hasPrefix("/") ? [] : base.split(separator: "/").map(String.init)
        for part in target.split(separator: "/") {
          if part == ".." { guard !components.isEmpty else { throw FileSummaryReader.Failure.unsupported }; components.removeLast() }
          else if part != "." { components.append(String(part)) }
        }
        let resolved = components.joined(separator: "/")
        guard entries[resolved] != nil, result[id] == nil else { throw FileSummaryReader.Failure.unsupported }
        result[id] = resolved
      }
      return result
    }
  }
}

private final class OfficeXMLNode {
  let name: String
  let attributes: [String: String]
  var text = ""
  var children: [OfficeXMLNode] = []
  init(name: String, attributes: [String: String]) { self.name = name; self.attributes = attributes }
  var relationshipID: String? { attributes.first { $0.key.hasSuffix(":id") }?.value }
  func descendants(_ name: String) -> [OfficeXMLNode] {
    children.flatMap { ($0.name == name ? [$0] : []) + $0.descendants(name) }
  }
  func prose() -> String {
    if name == "del" { return "" }
    if name == "t" { return text }
    if name == "tab" { return "\t" }
    if name == "br" || name == "cr" { return "\n" }
    let value = children.map { $0.prose() }.joined()
    return value + (name == "p" || name == "tr" ? "\n" : name == "tc" ? "\t" : "")
  }
}

private final class OfficeXMLParser: NSObject, XMLParserDelegate {
  var root: OfficeXMLNode?
  var stack: [OfficeXMLNode] = []
  var count = 0
  static func parse(_ data: Data) throws -> OfficeXMLNode {
    // DTD/entity declarations are unnecessary in OOXML and are rejected before parsing.
    guard let xml = String(data: data, encoding: .utf8), !xml.contains("<!DOCTYPE"), !xml.contains("<!ENTITY") else { throw FileSummaryReader.Failure.unsupported }
    let delegate = OfficeXMLParser()
    let parser = XMLParser(data: data)
    parser.shouldProcessNamespaces = true
    parser.shouldResolveExternalEntities = false
    parser.delegate = delegate
    guard parser.parse(), let root = delegate.root else { throw FileSummaryReader.Failure.unsupported }
    return root
  }
  func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
    count += 1
    guard !Task.isCancelled, count <= 100_000, stack.count < 128 else { parser.abortParsing(); return }
    let node = OfficeXMLNode(name: elementName, attributes: attributeDict)
    if let parent = stack.last { parent.children.append(node) } else { root = node }
    stack.append(node)
  }
  func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }
  func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
    guard let value = String(data: CDATABlock, encoding: .utf8) else { parser.abortParsing(); return }
    stack.last?.text += value
  }
  func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { _ = stack.popLast() }
}
