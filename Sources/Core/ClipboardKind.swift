import Foundation

enum ClipboardKind: String, Codable, CaseIterable, Identifiable {
    case text, link, image, files
    var id: Self { self }
    var title: String {
        switch self { case .text: "Text"; case .link: "Links"; case .image: "Images"; case .files: "Files" }
    }
    var symbol: String {
        switch self { case .text: "doc.text"; case .link: "link"; case .image: "photo"; case .files: "doc" }
    }
}

struct ClipboardFile: Codable, Equatable {
    let url: URL
    let bookmark: Data?
    let name: String
    let size: Int?
}
