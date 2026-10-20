import Foundation

/// Only a user-authored text instruction. Never shell code, tool access or background work.
struct TextHabit: Codable, Equatable, Identifiable, Sendable {
    enum Output: String, Codable, CaseIterable, Sendable {
        case replace, reading
        var title: String { self == .replace ? "Replace selected text" : "Show a result to copy" }
    }
    var id = UUID()
    var name = ""
    var instruction = ""
    var summary: String? = nil
    var output = Output.replace
    var filePlan: FileHabitPlan? = nil
    var destinationBookmark: Data? = nil
    var enabled = true
    /// Optional for compatibility with existing local and cloud archives.
    var iconName: String? = nil
    var resolvedIconName: String {
        if let iconName, Self.iconChoices.contains(where: { $0.symbol == iconName }) { return iconName }
        if filePlan != nil { return filePlan?.operation == .move ? "folder" : "pencil.line" }
        let text = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let rules: [(String, [String])] = [
            ("envelope", ["email", "mail", "courriel"]),
            ("character.bubble", ["translat", "tradu"]),
            ("list.bullet", ["summar", "resume", "recap", "key point"]),
            ("checklist", ["task", "tache", "todo"]),
            ("calendar", ["calendar", "event", "agenda"]),
            ("chevron.left.forwardslash.chevron.right", ["code", "json", "sql"]),
            ("square.and.pencil", ["writ", "redig", "reformul"]),
            ("checkmark", ["correct", "corrig", "fix"])
        ]
        return rules.first { rule in rule.1.contains { text.contains($0) } }?.0 ?? "sparkles"
    }
    static let iconChoices: [(symbol: String, label: String)] = [
        ("sparkles", "Sparkles"), ("square.and.pencil", "Writing"), ("pencil.line", "Rename"),
        ("checkmark", "Correction"), ("character.bubble", "Translation"), ("lightbulb", "Idea"),
        ("list.bullet", "Summary"), ("checklist", "Tasks"), ("envelope", "Email"),
        ("bubble.left", "Message"), ("calendar", "Calendar"), ("clock", "Time"),
        ("folder", "Folder"), ("doc.text", "Document"), ("doc.on.doc", "Documents"),
        ("archivebox", "Archive"), ("photo", "Image"), ("music.note", "Music"),
        ("chevron.left.forwardslash.chevron.right", "Code"), ("globe", "Web"),
        ("bag", "Shopping"), ("briefcase", "Work"), ("star", "Star"), ("heart", "Heart")
    ]
    /// Every saved action has a usable description, including older manual habits.
    var rankingDescription: String {
        let description = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return description.isEmpty ? instruction : description
    }
    func isEligible(in context: RecommendationContext) -> Bool {
        guard enabled, isValid else { return false }
        switch context.content {
        case .text: return filePlan == nil
        case .files: return !needsDestination && (context.source.map { filePlan?.accepts($0.files) == true } ?? false)
        case .none: return false
        }
    }
    var needsDestination: Bool { filePlan?.operation == .move && destinationBookmark?.isEmpty != false }
    var isValid: Bool { isSyncable && !needsDestination }
    var isSyncable: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 40
        && !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && instruction.unicodeScalars.count <= 1000
        && (filePlan == nil || filePlan!.isValid)
    }
    func normalized() -> Self {
        var value = self
        value.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.instruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        return value
    }
}

struct TextHabitRepository {
    let url: URL
    struct Archive: Codable { let version: Int; let habits: [TextHabit]; var sync: HabitSyncState? = nil }
    enum Failure: Error { case invalidArchive }
    func load() throws -> [TextHabit] { try loadArchive().habits }
    func loadArchive() throws -> Archive {
        guard FileManager.default.fileExists(atPath: url.path) else { return Archive(version: 1, habits: []) }
        let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: url))
        guard archive.version == 1 else { throw Failure.invalidArchive }
        try validate(archive.habits)
        return archive
    }
    func save(_ habits: [TextHabit], sync: HabitSyncState? = nil) throws {
        try validate(habits)
        let data = try JSONEncoder().encode(Archive(version: 1, habits: habits, sync: sync))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
    private func validate(_ habits: [TextHabit]) throws {
        guard habits.count <= 50, habits.allSatisfy(\.isSyncable),
              Set(habits.map(\.id)).count == habits.count else { throw Failure.invalidArchive }
    }
}
