import Foundation

struct AuthSession: Codable, Sendable {
    struct User: Codable, Sendable, Equatable {
        let id: UUID
        let email: String?
    }

    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let user: User

    func needsRefresh(at date: Date = .now) -> Bool {
        expiresAt.timeIntervalSince(date) < 60
    }

    var isValid: Bool { !accessToken.isEmpty && !refreshToken.isEmpty && expiresAt.timeIntervalSince1970.isFinite }
}
