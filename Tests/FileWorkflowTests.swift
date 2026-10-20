import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import TeroCore

final class FileWorkflowTests: XCTestCase {
  func testFilenameStyleForShortAndLongNames() throws {
    XCTAssertEqual(FileNameProposal.formatted("Orion Invoice"), "orionInvoice")
    XCTAssertEqual(FileNameProposal.formatted("Orion annual budget report"), "orion-annual-budget-report")
    XCTAssertEqual(FileNameProposal.formatted("Extraordinarily detailed documentation"), "extraordinarily-detailed-documentation")
    XCTAssertEqual(FileNameProposal.formatted("  Orion\tinvoice\n2026 "), "orionInvoice2026")
    XCTAssertEqual(FileNameProposal.formatted("orionInvoice"), "orionInvoice")
    XCTAssertEqual(FileNameProposal.formatted("PDF"), "pdf")
    let url = URL(fileURLWithPath: "/tmp/old.PDF")
    XCTAssertThrowsError(try FileNameProposal.targets([url], stems: ["---"]))
    XCTAssertEqual(try FileNameProposal.targets([url], stems: ["Orion annual budget report"])[0].lastPathComponent, "orion-annual-budget-report.PDF")
  }
  func testAINameBindingAndExtensionPreservation() throws {
    let names: [FileNameProposal] = [.init(id: "file-1", stem: "Orion Schedule"), .init(id: "file-0", stem: "Orion Invoice")]
    let ordered = try FileNameProposal.ordered(names, count: 2)
    XCTAssertEqual(ordered, ["orionInvoice", "orionSchedule"])
    let urls = [URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b.PDF")]
    XCTAssertEqual(try FileNameProposal.targets(urls, stems: ordered).map(\.lastPathComponent), ["orionInvoice.txt", "orionSchedule.PDF"])
    for invalid: [FileNameProposal] in [Array(names.prefix(1)), [names[0],names[0]], [.init(id:"file-0",stem:"../escape"),names[0]]] {
      XCTAssertThrowsError(try FileNameProposal.ordered(invalid, count: 2))
    }
    XCTAssertEqual(Action.renameFile.definition?.usesAI, true)
    XCTAssertEqual(Action.batchRename.definition?.usesAI, true)
  }
  func testNamingReadsActualContentAndRejectsChangedSources() async throws {
    let work = try LocalFileIO.workspace(); defer { try? FileManager.default.removeItem(at: work) }
    let file = work.appendingPathComponent("random.txt")
    try Data("Hello\nInvoice for Orion. Total 80 EUR.".utf8).write(to: file)
    let snapshot = try LocalFileIO.Snapshot(file)
    let input = try await FileSummaryReader().namingInputs([file], snapshots: [snapshot])
    XCTAssertEqual(input[0].id, "file-0")
    XCTAssertTrue(input[0].text!.contains("Total 80 EUR"))
    XCTAssertNil(input[0].file)
    let encoded = String(data: try JSONEncoder().encode(input), encoding: .utf8)!
    XCTAssertFalse(encoded.contains(file.path)); XCTAssertFalse(encoded.contains("random.txt"))
    try Data("Different content".utf8).write(to: file)
    do { _ = try await FileSummaryReader().namingInputs([file], snapshots: [snapshot]); XCTFail("Changed content accepted") } catch {}
  }
  func testFileCapabilitiesAndReadingDelivery() throws {
    let work = try LocalFileIO.workspace(); defer { try? FileManager.default.removeItem(at: work) }
    let a = work.appendingPathComponent("first.txt"), b = work.appendingPathComponent("second.txt")
    try Data("one".utf8).write(to: a); try Data("two".utf8).write(to: b)
    let files = [InvocationContext.FileObservation.read(a), .read(b)]
    XCTAssertFalse(FileWorkflowKind.rename.accepts(files)); XCTAssertTrue(FileWorkflowKind.batchRename.accepts(files))
    XCTAssertTrue(FileWorkflowKind.move.accepts(files)); XCTAssertTrue(FileWorkflowKind.rename.accepts(Array(files.prefix(1))))
    XCTAssertEqual(Action.summarizeFile.definition?.delivery(canReplace: false), .readingCard)
  }
  func testNameValidationAndTemplates() throws {
    for invalid in ["../escape", ".hidden", "a/b", "a:b", "", "\n"] { XCTAssertFalse(FileWorkflowEngine.validStem(invalid)) }
    let urls = [URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b.pdf")]
    XCTAssertEqual(try FileWorkflowEngine.renameTargets(urls, template: "file-{n}").map(\.lastPathComponent), ["file-01.txt", "file-02.pdf"])
  }
  func testRenameAndConflicts() async throws {
    let work = try LocalFileIO.workspace(); defer { try? FileManager.default.removeItem(at: work) }
    let a = work.appendingPathComponent("first.txt"), b = work.appendingPathComponent("second.txt")
    try Data("one".utf8).write(to: a); try Data("two".utf8).write(to: b)
    let engine = FileWorkflowEngine(), snapshots = try [a,b].map(LocalFileIO.Snapshot.init)
    let target = work.appendingPathComponent("taken.txt"); try Data("keep".utf8).write(to: target)
    do { _ = try await engine.relocate([a,b], targets: [work.appendingPathComponent("new.txt"), target], snapshots: snapshots); XCTFail("Conflict accepted") } catch {}
    XCTAssertTrue(FileManager.default.fileExists(atPath: a.path)); XCTAssertFalse(FileManager.default.fileExists(atPath: work.appendingPathComponent("new.txt").path))
    let renamed = try await engine.relocate([a,b], targets: FileWorkflowEngine.renameTargets([a,b], template: "test-{n}"), snapshots: snapshots)
    XCTAssertEqual(renamed.count, 2); XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
  }
  func testChangedSourceRefused() async throws {
    let work = try LocalFileIO.workspace(); defer { try? FileManager.default.removeItem(at: work) }
    let a = work.appendingPathComponent("first.txt"); try Data("one".utf8).write(to: a)
    let snapshot = try LocalFileIO.Snapshot(a); try Data("changed".utf8).write(to: a)
    let target = work.appendingPathComponent("moved.txt")
    do { _ = try await FileWorkflowEngine().relocate([a], targets: [target], snapshots: [snapshot]); XCTFail("Changed source accepted") } catch {}
    XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
  }
  func testUnsafeZipPathsAndSymlinksRefused() throws {
    let work = try LocalFileIO.workspace(); defer { try? FileManager.default.removeItem(at: work) }
    // Synthetic ZIPs are generated with a fixed Python program, no selected content.
    let python = Process(); python.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    python.arguments = ["-c", "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1],'w'); z.writestr('../escape.txt','bad'); z.close()", work.appendingPathComponent("unsafe.zip").path]
    try python.run(); python.waitUntilExit(); XCTAssertEqual(python.terminationStatus, 0)
    XCTAssertThrowsError(try SafeZip.entries(Data(contentsOf: work.appendingPathComponent("unsafe.zip"))))
    let link = work.appendingPathComponent("link.zip")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: work.appendingPathComponent("unsafe.zip"))
    XCTAssertThrowsError(try LocalFileIO.Snapshot(link))
  }

}
