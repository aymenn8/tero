import Foundation
import AppKit
import Observation

@MainActor @Observable final class ShoppingSession {
    private(set) var request: String
    var draft = ""
    var composing: Bool { request.isEmpty }
    var preferences = ""
    private(set) var result: ShoppingResult?
    private(set) var busy = false
    private(set) var error: String?
    private var previousPreferences = ""
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var requestID: UUID?
    @ObservationIgnored private var owner: UUID?
    let back: () -> Void
    let changed: () -> Void
    let denied: (Bool) -> Void
    init(request: String, back: @escaping () -> Void, changed: @escaping () -> Void, denied: @escaping (Bool) -> Void) {
        self.request = request; self.back = back; self.changed = changed; self.denied = denied
    }
    var editorHeight: CGFloat {
        guard composing else { return 50 }
        let measured = (draft as NSString).boundingRect(
            with: CGSize(width: 412, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: 14)]).height
        return min(140, max(50, ceil(measured) + 2))
    }
    var height: CGFloat {
        let content: CGFloat = composing ? editorHeight + 118 : result == nil ? 260 : 560
        return content + (error == nil ? 0 : 26)
    }
    func search(skip: Bool = false) {
        guard !busy else { return }
        if composing {
            let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }
            guard ShoppingRequest.input(request: value, preferences: "") != nil else { error = "Keep your request shorter to search."; return }
            request = value; draft = ""; error = nil; changed(); return
        }
        guard ShoppingRequest.isActivated else { error = "Product search is not connected yet."; return }
        let addition = skip ? "" : preferences.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result == nil || !addition.isEmpty || error != nil else { return }
        let combined = [previousPreferences, addition].filter { !$0.isEmpty }.joined(separator: "\n")
        guard let input = ShoppingRequest.input(request: request, preferences: combined) else { error = "Keep your request shorter to search."; return }
        let id = UUID(); requestID = id; owner = AccountStore.shared.user?.id
        busy = true; error = nil; changed()
        task = Task { [weak self] in
            guard let self else { return }
            defer { if self.requestID == id { self.busy = false; self.changed() } }
            do {
                guard let credential = await GatewayAccess.credential() else { throw CorrectionClient.Failure.unavailable }
                guard self.owner == AccountStore.shared.user?.id else { return }
                let value = try await CorrectionClient().shop(input, requestID: id, credential: credential)
                guard !Task.isCancelled, self.requestID == id, self.owner == AccountStore.shared.user?.id else { return }
                self.result = value; self.previousPreferences = combined; self.preferences = ""
            } catch {
                guard !Task.isCancelled, self.requestID == id, self.owner == AccountStore.shared.user?.id else { return }
                if error as? CorrectionClient.Failure == .unavailable { self.denied(true) }
                else if error as? CorrectionClient.Failure == .allowanceReached { self.denied(false) }
                else { self.error = "Couldn’t finish the search. Try again." }
            }
        }
    }
    func cancel() { task?.cancel(); task = nil; requestID = nil; busy = false }
}
