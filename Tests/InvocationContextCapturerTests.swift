import Foundation
import Testing
@testable import TeroCore

private final class FixtureContextReader: InvocationContextReading {
    typealias Element = Int
    var values: [Int: [InvocationContext.Attribute: String]] = [:]
    var parents: [Int: Int] = [:]
    var window: Int? = 99
    var limit = 100
    var reads = 0
    var excerptReads = 0
    var parentReads = 0
    var count = 2000
    var requestedRange: NSRange?
    var protectedOnSecondRead = false
    var subroleReads = 0
    var canRead: Bool { reads < limit }
    func text(_ attribute: InvocationContext.Attribute, from element: Int) -> String? {
        reads += 1
        if attribute == .subrole {
            subroleReads += 1
            if protectedOnSecondRead && subroleReads > 1 { return "AXSecureTextField" }
        }
        return values[element]?[attribute]
    }
    func parent(of element: Int) -> Int? { reads += 1; parentReads += 1; return parents[element] }
    func focusedWindow() -> Int? { reads += 1; return window }
    func characterCount(of element: Int) -> Int? { reads += 1; return count }
    func excerpt(from element: Int, range: NSRange) -> String? {
        reads += 1; excerptReads += 1; requestedRange = range
        return String(repeating: "fixture ", count: 300)
    }
    func capture(app: String = "com.example.unknown", editable: Bool = false,
                 available: Bool = true, selection: NSRange? = NSRange(location: 500, length: 10)) -> InvocationContext {
        InvocationContextCapturer.capture(using: self, focused: 1,
            initial: .init(capturedAt: .now, applicationID: app), editable: editable,
            selection: selection, selectedTextAvailable: available)
    }
}

@Test func genericNativeFieldCapturesLabelsAndBoundedExcerpt() {
    let reader = FixtureContextReader()
    reader.values = [1: [.role: "AXTextArea", .placeholder: "Write here", .description: "Message"],
                     2: [.role: "AXGroup", .title: "Draft"], 99: [.title: "Untitled"]]
    reader.parents = [1: 2]
    let context = reader.capture(editable: true)
    #expect(context.surface == .writing && context.webHost == nil)
    #expect(context.elementPlaceholder == "Write here" && context.windowTitle == "Untitled")
    #expect(context.containers == [.init(role: "AXGroup", label: "Draft")])
    #expect(context.nearbyText?.count == 960)
    #expect(reader.requestedRange == NSRange(location: 260, length: 490))
}

@Test func embeddedWebViewWorksWithoutBrowserOrSiteAllowlist() {
    let reader = FixtureContextReader()
    reader.values = [1: [.role: "AXStaticText", .url: "https://unrelated.example/link"],
                     2: [.role: "AXWebArea", .url: "https://arbitrary.example/document?secret=fixture#part"]]
    reader.parents = [1: 2]
    let context = reader.capture(app: "com.example.embedded")
    #expect(context.webHost == "arbitrary.example" && context.surface == .reading)
    #expect(context.containers.first?.role == "AXWebArea")
}

@Test func linkAndWindowTitleCannotMasqueradeAsCurrentPage() {
    let reader = FixtureContextReader()
    reader.values = [1: [.role: "AXLink", .url: "https://linked.example"],
                     99: [.title: "https://title.example — compose"]]
    let context = reader.capture(available: false)
    #expect(context.webHost == nil && context.surface == .unknown && context.nearbyText == nil)
    #expect(reader.excerptReads == 0)
}

@Test func protectedFieldNeverReadsLabelsOrSurroundingText() {
    let reader = FixtureContextReader()
    reader.values = [1: [.subrole: "AXSecureTextField", .title: "must not read"]]
    let context = reader.capture(editable: true)
    #expect(context.capture == .protectedField)
    #expect(context.elementLabel == nil && context.windowTitle == nil && context.nearbyText == nil)
    #expect(reader.reads == 1 && reader.excerptReads == 0)
}

@Test func fieldBecomingProtectedDiscardsAlreadyCapturedDetails() {
    let reader = FixtureContextReader()
    reader.values = [1: [.role: "AXTextArea", .title: "Discard me"]]
    reader.protectedOnSecondRead = true
    let context = reader.capture(editable: true)
    #expect(context.capture == .protectedField && context.elementLabel == nil)
    #expect(reader.excerptReads == 0)
}

@Test func missingAttributesAndExpiredBudgetProducePartialContext() {
    let missing = FixtureContextReader()
    let context = missing.capture(available: false)
    #expect(context.capture == .partial && context.webHost == nil && context.elementRole == nil)
    let timedOut = FixtureContextReader(); timedOut.limit = 0
    let partial = timedOut.capture(editable: true)
    #expect(partial.capture == .partial && partial.surface == .unknown && timedOut.reads == 0)
    #expect(partial.limitations.contains(.readBudgetReached))
    #expect(context.limitations.contains(.roleUnavailable))
}

@Test func cyclicAncestryCannotCauseUnboundedCapture() {
    let reader = FixtureContextReader()
    reader.values = [1: [.role: "AXTextArea"], 2: [.role: "AXGroup"]]
    reader.parents = [1: 2, 2: 1]
    let context = reader.capture(available: false)
    #expect(reader.parentReads == 16 && context.containers.count <= 15)
    #expect(context.limitations.contains(.ancestorLimitReached))
    #expect(context.webHost == nil)
}

@Test func boundedCaptureDoesNotReadExcerptAfterBudgetExpires() {
    let reader = FixtureContextReader()
    reader.limit = 3; reader.values = [1: [.role: "AXTextArea"]]
    let context = reader.capture(editable: true)
    #expect(context.capture == .partial && reader.excerptReads == 0)
}

@Test func snapshotCollectorDoesNotReuseOldPageEvidence() {
    let reader = FixtureContextReader(); reader.limit = 0
    let old = InvocationContext(capturedAt: .now, applicationID: "com.example", windowTitle: "Old",
                                webHost: "old.example", nearbyText: "old text")
    let result = InvocationContextCapturer.capture(using: reader, focused: 1, initial: old,
        editable: false, selection: nil, selectedTextAvailable: false)
    #expect(result.webHost == nil && result.nearbyText == nil && result.windowTitle == nil)
}

@Test func deepComposerAncestryRetainsActualPageHost() {
    let reader = FixtureContextReader()
    reader.values[1] = [.role: "AXTextArea", .placeholder: "What is happening?!"]
    for i in 2...11 { reader.values[i] = [.role: "AXGroup"]; reader.parents[i-1] = i }
    reader.values[12] = [.role: "AXWebArea", .url: "https://x.com/compose/post?private=draft"]
    reader.parents[11] = 12
    let context = reader.capture(editable: true)
    #expect(context.webHost == "x.com")
    #expect(context.surface == .writing)
    #expect(!context.limitations.contains(.ancestorLimitReached))
}
