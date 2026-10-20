import Foundation

/// Injectable boundary: tests provide synthetic accessibility trees, the app uses macOS AX.
protocol InvocationContextReading {
    associatedtype Element
    var canRead: Bool { get }
    func text(_ attribute: InvocationContext.Attribute, from element: Element) -> String?
    func parent(of element: Element) -> Element?
    func focusedWindow() -> Element?
    func characterCount(of element: Element) -> Int?
    func excerpt(from element: Element, range: NSRange) -> String?
}
