import Foundation

/// First local policy. Candidate eligibility stays in code when semantic ranking is added.
/// No raw content persistence, behavioral tracking, network calls or autonomous effects.
enum RecommendationEngine {

    /// Explicit compatible file habits remain discoverable if semantic ranking is unavailable.
    static func rank(context: RecommendationContext, personalActions: [TextHabit]) -> [ActionRecommendation] {
        let personal = personalActions.filter { $0.isEligible(in: context) }.map {
            ActionRecommendation(target: .habit($0.id), priority: $0.filePlan == nil ? 20 : 100, reason: .explicitHabit)
        }
        return (personal + rank(context: context)).enumerated().sorted {
            $0.element.priority == $1.element.priority ? $0.offset < $1.offset : $0.element.priority > $1.element.priority
        }.map(\.element)
    }

    static func rank(context: RecommendationContext) -> [ActionRecommendation] {
        switch context.content {
        case .none:
            return []
        case .files:
            return ActionCatalog.definitions.compactMap { definition -> ActionRecommendation? in
                guard let priority = definition.priority(in: context) else { return nil }
                return .init(target: .native(definition.id), priority: priority, reason: .utility)
            }.sorted { $0.priority > $1.priority }
        case .text(let numeric, let editable):
            return ActionCatalog.definitions.compactMap { definition -> ActionRecommendation? in
                guard let priority = definition.priority(in: context) else { return nil }
                let reason: ActionRecommendation.Reason = numeric ? .numericSelection : editable == nil ? .generalText
                    : editable == true ? .writingContext : .readingContext
                return .init(target: .native(definition.id), priority: priority, reason: reason)
            }.sorted { $0.priority > $1.priority }
        }
    }
}
