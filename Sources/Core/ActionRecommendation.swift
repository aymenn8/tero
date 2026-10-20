import Foundation

struct ActionRecommendation: Equatable, Sendable {
    enum Target: Equatable, Hashable, Sendable {
        case native(Action)
        case habit(UUID)
        var rankingID: String {
            switch self {
            case .native(let action): action.rawValue
            case .habit(let id): "habit_" + id.uuidString.lowercased()
            }
        }
    }
    enum Reason: Equatable, Sendable {
        case numericSelection, writingContext, readingContext, generalText, explicitHabit, utility
    }
    let target: Target
    /// Relative local policy priority, NOT a model probability or permission to execute.
    let priority: Int
    let reason: Reason
}

/// A frozen recommendation order, shown three at a time with a nine-action ceiling.
enum ActionRecommendationPages {
    static func targets(_ recommendations: [ActionRecommendation], page: Int) -> [ActionRecommendation.Target] {
        let candidates = Array(recommendations.prefix(9)).map(\.target)
        let last = max(0, (candidates.count - 1) / 3)
        let current = min(max(page, 0), last)
        let modes = Array(candidates.dropFirst(current * 3).prefix(3))
        return (current > 0 ? [.native(.back)] : [.native(.search)]) + modes
            + [.native(current < last ? .more : .allActions)]
    }
}
