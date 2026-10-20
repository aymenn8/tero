import Foundation

enum AuthProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case google, apple, github
    var id: String { rawValue }
    var title: String {
        switch self {
        case .google: "Google"
        case .apple: "Apple"
        case .github: "GitHub"
        }
    }
}
