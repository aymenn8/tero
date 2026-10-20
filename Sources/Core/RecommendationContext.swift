import Foundation

/// Invocation-local facts only. Unknown editability must not be treated as permission to paste.
struct RecommendationContext: Equatable, Sendable {
    enum Content: Equatable, Sendable {
        case text(isNumber: Bool, editable: Bool?)
        case files(count: Int, allAudio: Bool)
        case none
    }
    let selectionText: String?
    let applicationID: String?
    let content: Content
    let source: InvocationContext?

    init(applicationID: String?, content: Content) {
        self.applicationID = applicationID
        self.source = nil
        self.selectionText = nil
        self.content = content
    }

    init(selection: SelectionReadout, applicationID: String?) {
        self.applicationID = selection.context?.applicationID ?? applicationID
        self.source = selection.context
        if case .selected(let text) = selection.status { self.selectionText = text } else { self.selectionText = nil }
        if case .selected(let text) = selection.status, !text.isEmpty {
            content = .text(isNumber: QuickCalculation.number(text) != nil,
                            editable: selection.metadata?.isEditable)
        } else {
            content = .none
        }
    }

    init(fileContext: InvocationContext) {
        applicationID = fileContext.applicationID
        source = fileContext
        selectionText = nil
        content = .files(count: fileContext.files.count, allAudio: false)
    }
}
