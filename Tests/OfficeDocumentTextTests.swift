import Foundation
import PDFKit
import XCTest
@testable import TeroCore

final class OfficeDocumentTextTests: XCTestCase {
  private func package(_ parts: [String: String], ext: String, folder: URL) throws -> URL {
    let contents = folder.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    for (name, text) in parts {
      let file = contents.appendingPathComponent(name)
      try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(text.utf8).write(to: file)
    }
    let result = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    process.currentDirectoryURL = contents; process.arguments = ["-q", "-r", result.path, "."]
    try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
    return result
  }
  func testWordParagraphsTablesUnicodeAndDeletedText() async throws {
    let folder = try LocalFileIO.workspace(); defer { try? FileManager.default.removeItem(at: folder) }
    let source = try package(["word/document.xml": """
    <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>Réunion 東京 &amp; budget</w:t></w:r><w:del><w:r><w:t>deleted secret</w:t></w:r></w:del></w:p><w:tbl><w:tr><w:tc><w:p><w:r><w:t>Orion</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>120 €</w:t></w:r></w:p></w:tc></w:tr></w:tbl></w:body></w:document>
    """, "word/header1.xml": "<w:hdr xmlns:w=\"urn:w\"><w:p><w:r><w:t>Header</w:t></w:r></w:p></w:hdr>"], ext: "docx", folder: folder)
    let original = try Data(contentsOf: source)
    let text = try await OfficeDocumentText.read(source, workspace: folder)
    XCTAssertTrue(text.contains("Réunion 東京 & budget")); XCTAssertTrue(text.contains("120 €")); XCTAssertTrue(text.contains("Header"))
    XCTAssertFalse(text.contains("deleted secret"))
    let inputs = try await FileSummaryReader().namingInputs([source], snapshots: [.init(source)])
    let payload = try XCTUnwrap(inputs.first?.file)
    let pdf = try XCTUnwrap(PDFDocument(data: try XCTUnwrap(Data(base64Encoded: payload.data))))
    XCTAssertTrue(pdf.string?.contains("Réunion") == true)
    XCTAssertEqual(try Data(contentsOf: source), original)
  }
  func testWorkbookRelationshipsAllSheetsSparseCellsAndCachedFormulas() async throws {
    let folder = try LocalFileIO.workspace(); defer { try? FileManager.default.removeItem(at: folder) }
    let source = try package([
      "xl/workbook.xml": "<workbook xmlns:r=\"urn:r\"><sheets><sheet name=\"Second first\" r:id=\"r2\"/><sheet name=\"First last\" r:id=\"r1\"/></sheets></workbook>",
      "xl/_rels/workbook.xml.rels": "<Relationships><Relationship Id=\"r1\" Target=\"worksheets/sheet1.xml\"/><Relationship Id=\"r2\" Target=\"worksheets/sheet2.xml\"/></Relationships>",
      "xl/sharedStrings.xml": "<sst><si><r><t>Pro</t></r><r><t>ject</t></r></si></sst>",
      "xl/worksheets/sheet1.xml": "<worksheet><sheetData><row><c r=\"A1\" t=\"s\"><v>0</v></c><c r=\"D1\"><f>B1*2</f><v>240</v></c></row></sheetData></worksheet>",
      "xl/worksheets/sheet2.xml": "<worksheet><sheetData><row><c r=\"B2\" t=\"inlineStr\"><is><t>Budget</t></is></c><c r=\"C2\"><f>SUM(A1:A2)</f></c></row></sheetData></worksheet>"
    ], ext: "xlsx", folder: folder)
    let text = try await OfficeDocumentText.read(source, workspace: folder)
    XCTAssertTrue(text.contains("A1: Project")); XCTAssertTrue(text.contains("D1: 240"))
    XCTAssertTrue(text.contains("C2: =SUM(A1:A2) [saved result unavailable]"))
    XCTAssertLessThan(try XCTUnwrap(text.range(of: "Second first")?.lowerBound), try XCTUnwrap(text.range(of: "First last")?.lowerBound))
  }
  func testPresentationUsesSlideOrderAndRefusesExternalSlide() async throws {
    let folder = try LocalFileIO.workspace(); defer { try? FileManager.default.removeItem(at: folder) }
    var parts = [
      "ppt/presentation.xml": "<p:presentation xmlns:p=\"urn:p\" xmlns:r=\"urn:r\"><p:sldIdLst><p:sldId r:id=\"r2\"/><p:sldId r:id=\"r1\"/></p:sldIdLst></p:presentation>",
      "ppt/_rels/presentation.xml.rels": "<Relationships><Relationship Id=\"r1\" Target=\"slides/slide1.xml\"/><Relationship Id=\"r2\" Target=\"slides/slide2.xml\"/></Relationships>",
      "ppt/slides/slide1.xml": "<slide><p><t>Last</t></p></slide>", "ppt/slides/slide2.xml": "<slide><p><t>First</t></p></slide>"
    ]
    let source = try package(parts, ext: "pptx", folder: folder)
    let text = try await OfficeDocumentText.read(source, workspace: folder)
    XCTAssertTrue(text.hasPrefix("Slide 1\nFirst")); XCTAssertTrue(text.contains("Slide 2\nLast"))
    parts["ppt/_rels/presentation.xml.rels"] = "<Relationships><Relationship Id=\"r2\" Target=\"https://example.com/slide.xml\" TargetMode=\"External\"/></Relationships>"
    let external = try package(parts, ext: "pptx", folder: folder)
    do { _ = try await OfficeDocumentText.read(external, workspace: folder); XCTFail("External input must fail") } catch { }
  }
  func testRejectsEntitiesBrokenPackagesEmptyAndOversizedSummary() async throws {
    let folder = try LocalFileIO.workspace(); defer { try? FileManager.default.removeItem(at: folder) }
    let source = try package(["word/document.xml": "<!DOCTYPE document [<!ENTITY attack SYSTEM 'file:///etc/passwd'>]><document><t>&attack;</t></document>"], ext: "docx", folder: folder)
    do { _ = try await FileSummaryReader().prepare(source); XCTFail("DTD must fail") } catch { }
    let empty = try package(["word/document.xml": "<document><body><p/></body></document>"], ext: "docx", folder: folder)
    do { _ = try await FileSummaryReader().prepare(empty); XCTFail("Empty document must fail") } catch LocalFileIO.Failure.noText { }
    let broken = folder.appendingPathComponent("broken.docx"); try Data("bad zip".utf8).write(to: broken)
    do { _ = try await FileSummaryReader().prepare(broken); XCTFail("Bad zip must fail") } catch { }
    let long = folder.appendingPathComponent("long.txt")
    try Data(String(repeating: "A long paragraph to paginate without silently truncating the input.\n", count: 4000).utf8).write(to: long)
    do { _ = try await FileSummaryReader().prepare(long); XCTFail("More than 30 pages must fail") } catch FileSummaryReader.Failure.tooLarge { }
    let cancelled = Task { try await FileSummaryReader().prepare(source) }; cancelled.cancel()
    do { _ = try await cancelled.value; XCTFail("Cancellation must fail") } catch is CancellationError { }
  }
  func testReadableFamiliesExcludeLegacyOffice() {
    for ext in ["doc", "xls", "ppt", "odt", "ods", "odp", "rtf"] {
      XCTAssertNil(DocumentFamily(URL(fileURLWithPath: "/tmp/input.\(ext)")))
    }
    XCTAssertEqual(DocumentFamily(URL(fileURLWithPath: "/tmp/input.xlsx")), .spreadsheet)
    XCTAssertEqual(DocumentFamily(URL(fileURLWithPath: "/tmp/input.docx")), .document)
  }
}
