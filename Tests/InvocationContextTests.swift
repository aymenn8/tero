import Foundation
import Testing
@testable import TeroCore

@Test func siteContextDropsSensitiveURLComponentsAndRejectsLookalikes() {
    #expect(InvocationContext.host(from: "https://mail.google.com/mail/u/0/?token=secret#inbox/123") == "mail.google.com")
    #expect(InvocationContext.host(from: "https://user:secret@x.com/") == nil)
    #expect(InvocationContext.host(from: "file:///private/example") == nil)
    #expect(InvocationContext.host(from: "javascript:alert(1)") == nil)
    var context = InvocationContext(capturedAt: .now, applicationID: "com.example.app")
    context.windowTitle = "A named website — Compose"
    #expect(context.webHost == nil && context.surface == .unknown)
    #expect(InvocationContext.host(from: "https://sub.example.org/page") == "sub.example.org")

}

@Test func roleEvidenceDoesNotPretendToKnowWebComposerOrReadingState() {
    #expect(InvocationContext.surface(role: "AXTextArea", editable: true) == .writing)
    #expect(InvocationContext.surface(role: "AXStaticText", editable: false) == .reading)
    #expect(InvocationContext.surface(role: "AXTextArea", editable: false) == .unknown)
    #expect(InvocationContext.surface(role: nil, editable: false) == .unknown)
    let application = InvocationContext(capturedAt: .now, applicationID: "com.example.reader")
    #expect(application.surface == .unknown)
}

@Test func nearbyTextRangeIsBoundedAndRejectsInvalidUTF16Ranges() {
    #expect(InvocationContext.excerptRange(selection: NSRange(location: 500, length: 20), total: 1000) == NSRange(location: 260, length: 500))
    #expect(InvocationContext.excerptRange(selection: NSRange(location: 0, length: 0), total: 20) == NSRange(location: 0, length: 20))
    #expect(InvocationContext.excerptRange(selection: NSRange(location: 0, length: 10000), total: 10000)?.length == 960)
    #expect(InvocationContext.excerptRange(selection: NSRange(location: 10, length: 20), total: 15) == nil)
    #expect(InvocationContext.excerptRange(selection: NSRange(location: NSNotFound, length: 1), total: 10) == nil)
    #expect(InvocationContext.excerptRange(selection: NSRange(location: 0, length: Int.max), total: 10) == nil)
}

@Test func recommendationReceivesSnapshotWithoutChangingExecutionPermission() {
    var readout = SelectionReadout(applicationName: "Browser", processIdentifier: 1, status: .selected("example"))
    readout.context = InvocationContext(capturedAt: .now, applicationID: "com.google.Chrome", surface: .writing, webHost: "mail.google.com")
    let recommendation = RecommendationContext(selection: readout, applicationID: nil)
    #expect(recommendation.source?.webHost == "mail.google.com")
    #expect(recommendation.applicationID == "com.google.Chrome")
    #expect(!readout.canPaste)
    #expect(RecommendationEngine.rank(context: recommendation).first?.target == .native(.explain))
}

@Test func fileContextReadsMixedMetadataWithoutSummingFolderContents() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("sample.txt")
    try Data("hello".utf8).write(to: file)
    let link = directory.appendingPathComponent("shortcut")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
    let observations = [file, directory, link].map { InvocationContext.FileObservation.read($0) }
    #expect(observations[0].name == "sample.txt")
    #expect(observations[0].extensionName == "txt")
    #expect(observations[0].byteCount == 5)
    #expect(observations[0].isDirectory == false)
    #expect(observations[0].typeIdentifier != nil)
    #expect(observations[0].parentPath == directory.path)
    #expect(observations[1].isDirectory == true)
    #expect(observations[1].byteCount == nil)
    #expect(observations[2].isSymbolicLink == true)
}

@Test func unavailableAndSkippedFileMetadataRemainUnknown() {
    let missing = URL(fileURLWithPath: "/tmp/tero-missing-\(UUID().uuidString)/missing.txt")
    for observation in [InvocationContext.FileObservation.read(missing),
                        InvocationContext.FileObservation.read(missing, includeMetadata: false)] {
        #expect(observation.name == "missing.txt")
        #expect(!observation.metadataAvailable)
        #expect(observation.byteCount == nil)
        #expect(observation.isDirectory == nil)
        #expect(observation.typeIdentifier == nil)
    }
}
