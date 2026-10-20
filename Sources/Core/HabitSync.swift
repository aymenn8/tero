import Foundation

/// Durable outbox in the same atomic archive as the habits. Never shared between accounts.
struct HabitSyncState: Codable, Equatable, Sendable {
    var pending: [UUID: UUID] = [:]
    var deleted: [UUID: UUID] = [:]
    mutating func save(_ id: UUID) { pending[id] = UUID(); deleted[id] = nil }
    mutating func remove(_ id: UUID) { pending[id] = nil; deleted[id] = UUID() }
}

/// Explicit whitelist: no selection, samples, local paths or security-scoped bookmarks.
struct CloudHabit: Codable, Sendable {
    struct Definition: Codable, Sendable {
        var schemaVersion = "1"
        let instruction: String
        let summary: String?
        let output: TextHabit.Output
        let filePlan: FileHabitPlan?
        var iconName: String? = nil
    }
    let id: UUID
    let user_id: UUID
    let name: String
    let enabled: Bool
    let definition: Definition
    init(_ habit: TextHabit, owner: UUID) {
        id = habit.id; user_id = owner; name = habit.name; enabled = habit.enabled
        definition = Definition(instruction: habit.instruction, summary: habit.summary,
                                output: habit.output, filePlan: habit.filePlan, iconName: habit.iconName)
    }
    func habit(local: TextHabit?) throws -> TextHabit {
        guard definition.schemaVersion == "1" else { throw TextHabitRepository.Failure.invalidArchive }
        let bookmark = local?.filePlan == definition.filePlan ? local?.destinationBookmark : nil
        let habit = TextHabit(id: id, name: name, instruction: definition.instruction,
                             summary: definition.summary, output: definition.output,
                             filePlan: definition.filePlan, destinationBookmark: bookmark, enabled: enabled, iconName: definition.iconName)
        guard habit.isSyncable else { throw TextHabitRepository.Failure.invalidArchive }
        return habit
    }
}

enum HabitSyncMerge {
    static func merge(local: [TextHabit], remote: [CloudHabit], state: HabitSyncState, owner: UUID) throws -> [TextHabit] {
        guard remote.count <= 50, remote.allSatisfy({ $0.user_id == owner }), Set(remote.map(\.id)).count == remote.count else {
            throw TextHabitRepository.Failure.invalidArchive
        }
        var merged: [TextHabit] = []
        for row in remote where state.deleted[row.id] == nil {
            let existing = local.first { $0.id == row.id }
            if state.pending[row.id] != nil, let existing { merged.append(existing) }
            else { merged.append(try row.habit(local: existing)) }
        }
        for habit in local where state.pending[habit.id] != nil && !merged.contains(where: { $0.id == habit.id }) {
            merged.append(habit)
        }
        guard merged.count <= 50 else { throw TextHabitRepository.Failure.invalidArchive }
        return merged.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
