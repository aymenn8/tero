import Foundation

/// Generated draft and disposable sample; only the confirmed instructions become a habit.
struct HabitDesign: Codable, Sendable {
    let name: String
    let instruction: String
    let summary: String
    let sample: String
    let question: String?
    var filePlan: FileHabitPlan? = nil
    var fileSamples: [FileHabitSample]? = nil
    /// A filename case conversion is a file operation, never a selected-text habit.
    var needsFileRenamePlan: Bool {
        let value = instruction.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let filenames = ["filename", "file name", "nom de fichier", "noms de fichiers"].contains { value.contains($0) }
        let caseConversion = ["camelcase", "camel case", "snake_case", "snake case", "kebab-case", "kebab case"].contains { value.contains($0) }
        return filenames && caseConversion && filePlan == nil
    }
    var isValid: Bool {
        if let question {
            return !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && question.count <= 240
                && name.isEmpty && instruction.isEmpty && summary.isEmpty && sample.isEmpty && filePlan == nil && (fileSamples ?? []).isEmpty
        }
        return TextHabit(name: name, instruction: instruction).isValid
            && !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && summary.count <= 240
            && (filePlan.map { $0.isValid && sample.isEmpty && FileHabitSample.valid(fileSamples ?? [], plan: $0) }
                ?? (!(sample.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) && sample.unicodeScalars.count <= 1000 && (fileSamples ?? []).isEmpty))
    }
}

struct FileHabitPlan: Codable, Equatable, Sendable {
    enum Operation: String, Codable, Sendable { case rename, move }
    let operation: Operation
    let extensions: [String]
    let nameContains: [String]
    var usesContents: Bool? = nil
    var isValid: Bool {
        (operation != .move || usesContents != true) && extensions.count <= 8 && Set(extensions).count == extensions.count
            && extensions.allSatisfy { !$0.isEmpty && $0.count <= 12 && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) } }
            && nameContains.count <= 5 && nameContains.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 60 }
    }
    func accepts(_ url: URL) -> Bool {
        (extensions.isEmpty || extensions.contains { $0.lowercased() == url.pathExtension.lowercased() })
            && (nameContains.isEmpty || nameContains.contains { url.lastPathComponent.localizedCaseInsensitiveContains($0) })
    }
    func accepts(_ files: [InvocationContext.FileObservation]) -> Bool {
        !files.isEmpty && files.count <= 20 && files.allSatisfy {
            $0.url.isFileURL && $0.metadataAvailable && $0.isDirectory == false && $0.isSymbolicLink == false && accepts($0.url)
        }
    }
}
struct FileHabitSample: Codable, Equatable, Sendable {
    let name: String
    let content: String
    static func valid(_ samples: [Self], plan: FileHabitPlan) -> Bool {
        (1...3).contains(samples.count) && Set(samples.map { $0.name.lowercased() }).count == samples.count
            && samples.allSatisfy { FileWorkflowEngine.validStem($0.name) && $0.content.count <= 1000 && plan.accepts(URL(fileURLWithPath: "/" + $0.name)) }
    }
}
