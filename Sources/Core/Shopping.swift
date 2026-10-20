import Foundation

struct ShoppingProduct: Codable, Identifiable, Sendable, Equatable {
    var id: String { url }
    let name: String
    let price: String
    let reason: String
    let tradeoff: String
    let url: String
    let imageURL: String?
    var link: URL? { ShoppingRequest.publicURL(url) }
    var image: URL? { imageURL.flatMap(ShoppingRequest.publicURL) }
    var valid: Bool {
        link != nil && !name.isEmpty && name.count <= 120 && price.count <= 100
        && !reason.isEmpty && reason.count <= 400 && tradeoff.count <= 300
        && (imageURL == nil || image != nil)
    }
}
struct ShoppingResult: Codable, Sendable {
    let requestID: UUID
    let summary: String
    let products: [ShoppingProduct]
    var valid: Bool {
        summary.count <= 600 && products.count <= 3 && products.allSatisfy(\.valid)
        && Set(products.map(\.id)).count == products.count
    }
}
enum ShoppingRequest {
    // Enabled after the shared search endpoint and ranking catalog are deployed.
    static let isActivated = true
    static func publicURL(_ raw: String) -> URL? {
        guard raw.count <= 2048, let url = URL(string: raw), url.scheme == "https",
              let host = url.host?.lowercased(), host.contains("."), !host.contains(":"),
              host != "localhost", !host.hasSuffix(".local"), !host.hasSuffix(".localhost"),
              host.range(of: "^[0-9.]+$", options: .regularExpression) == nil,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
    static let routingCandidates = ["shop", "explain"]
    static func shouldShowProducts(_ scores: [SemanticScore]) -> Bool {
        let candidates = routingCandidates.compactMap(Action.init(rawValue:)).map {
            ActionRecommendation(target: .native($0), priority: 0, reason: .generalText)
        }
        guard SemanticRankingPolicy.apply(scores, to: candidates) != nil,
              let shopping = scores.first(where: { $0.id == "shop" }),
              let answer = scores.first(where: { $0.id == "explain" }) else { return false }
        // Only a clearly relevant purchase need opens product cards. Ties and
        // weak evidence remain ordinary questions, including product explanations.
        return isActivated && shopping.score >= 2 && shopping.score > answer.score
    }
    static func input(request: String, preferences: String) -> String? {
        struct Input: Encodable { let request: String; let preferences: String; let locale: String }
        guard !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              request.count <= 3000, preferences.count <= 600 else { return nil }
        let input = Input(request: request, preferences: preferences, locale: Locale.current.identifier)
        guard let data = try? JSONEncoder().encode(input), let value = String(data: data, encoding: .utf8), value.count <= 4000 else { return nil }
        return value
    }
}
