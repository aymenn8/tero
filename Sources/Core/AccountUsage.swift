import Foundation

struct AccountUsage: Decodable, Sendable {
    let plan: String
    let rankRemaining: Int
    let actionRemaining: Int
    let usagePercent: Double
    let resetAt: String
    let creditsRemainingEUR: Double
    let canRank: Bool
    let canUseAI: Bool
    /// Display the available allowance; the server reports consumed Pro usage.
    var remainingPercent: Double {
        if plan == "pro" { return 100 - min(100, max(0, usagePercent)) }
        return Double(min(3, max(0, rankRemaining)) + min(3, max(0, actionRemaining))) / 6 * 100
    }
    var resetDate: Date? {
        (try? Date(resetAt, strategy: Self.fractionalISO8601)) ?? (try? Date(resetAt, strategy: .iso8601))
    }
    private static let fractionalISO8601 = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
}
