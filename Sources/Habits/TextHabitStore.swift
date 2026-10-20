import Foundation
import Observation

@MainActor @Observable final class TextHabitStore {
    static let shared = TextHabitStore()
    private(set) var habits: [TextHabit] = []
    private(set) var error: String?
    private(set) var loadFailed = false
    private(set) var isSyncing = false
    private(set) var lastSynced: Date?
    private var owner: String?
    private var repository: TextHabitRepository?
    private var state = HabitSyncState()
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private let client = HabitSyncClient()

    var syncDescription: String {
        if owner == "local" { return "Saved on this Mac. Sign in to sync your habits." }
        if isSyncing { return "Syncing your private habits…" }
        if !state.pending.isEmpty || !state.deleted.isEmpty { return "Saved on this Mac. Changes are waiting to sync." }
        return lastSynced == nil ? "Your habits are private to your account." : "Synced to your account. Available offline on this Mac."
    }

    func refreshOwner() {
        let next = AccountStore.shared.user?.id.uuidString ?? "local"
        guard next != owner else { syncNow(); return }
        syncTask?.cancel(); retryTask?.cancel(); syncTask = nil
        generation = UUID(); owner = next; habits = []; error = nil; loadFailed = false
        isSyncing = false; lastSynced = nil; state = HabitSyncState()
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.aymenkadri.tero.dev")
        repository = TextHabitRepository(url: directory.appendingPathComponent("text-habits-\(next)-v1.json"))
        do {
            let archive = try repository!.loadArchive()
            habits = archive.habits
            if let saved = archive.sync { state = saved }
            else if next != "local" {
                // One-time upload of legacy habits already scoped to this account.
                for habit in habits { state.save(habit.id) }
                try repository!.save(habits, sync: state)
            }
        } catch { loadFailed = true; self.error = "Your habits could not be loaded. The saved file has been preserved." }
        guard next != "local", !loadFailed else { return }
        syncNow()
        let expected = generation
        retryTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                guard let self, self.generation == expected else { return }
                self.syncNow()
            }
        }
    }

    @discardableResult func save(_ habit: TextHabit) -> Bool {
        refreshOwner()
        var next = habits
        let value = habit.normalized()
        if let index = next.firstIndex(where: { $0.id == value.id }) { next[index] = value }
        else { next.append(value) }
        var queue = state; queue.save(value.id)
        guard persist(next, state: queue) else { return false }
        syncNow(); return true
    }
    func remove(_ id: UUID) {
        refreshOwner()
        var queue = state; queue.remove(id)
        if persist(habits.filter { $0.id != id }, state: queue) { syncNow() }
    }
    func setEnabled(_ value: Bool, id: UUID) {
        refreshOwner()
        guard var habit = habits.first(where: { $0.id == id }) else { return }
        habit.enabled = value; save(habit)
    }
    private func persist(_ next: [TextHabit], state: HabitSyncState) -> Bool {
        guard !loadFailed, let repository else { return false }
        do { try repository.save(next, sync: state); habits = next; self.state = state; error = nil; return true }
        catch { self.error = "Could not save your changes. Previous habits are unchanged."; return false }
    }

    func syncNow() {
        if state.pending.isEmpty, state.deleted.isEmpty, let lastSynced, Date().timeIntervalSince(lastSynced) < 25 { return }
        guard syncTask == nil, !loadFailed, let owner, let identity = UUID(uuidString: owner),
              AccountStore.shared.user?.id == identity else { return }
        let expected = generation
        isSyncing = true
        syncTask = Task { [weak self] in
            guard let self else { return }
            defer { if generation == expected { syncTask = nil; isSyncing = false } }
            do {
                guard let token = try await AccountStore.shared.accessToken() else { throw AuthFailure.expiredSession }
                try checkOwner(identity, expected: expected)
                // Acknowledgements match the specific mutation, so edits made in flight stay queued.
                while !state.pending.isEmpty || !state.deleted.isEmpty {
                    let batch = state
                    for (id, version) in batch.deleted {
                        try checkOwner(identity, expected: expected)
                        try await client.remove(id, owner: identity, token: token)
                        try checkOwner(identity, expected: expected)
                        if state.deleted[id] == version {
                            var queue = state; queue.deleted[id] = nil
                            guard persist(habits, state: queue) else { throw AuthFailure.unavailable }
                        }
                    }
                    for (id, version) in batch.pending {
                        try checkOwner(identity, expected: expected)
                        guard state.pending[id] == version, let habit = habits.first(where: { $0.id == id }) else { continue }
                        try await client.save(habit, owner: identity, token: token)
                        try checkOwner(identity, expected: expected)
                        if state.pending[id] == version {
                            var queue = state; queue.pending[id] = nil
                            guard persist(habits, state: queue) else { throw AuthFailure.unavailable }
                        }
                    }
                }
                let remote = try await client.fetch(owner: identity, token: token)
                try checkOwner(identity, expected: expected)
                let merged = try HabitSyncMerge.merge(local: habits, remote: remote, state: state, owner: identity)
                guard persist(merged, state: state) else { throw AuthFailure.unavailable }
                lastSynced = .now
            } catch {
                guard generation == expected, !Task.isCancelled else { return }
                self.error = "Your habits are safe on this Mac. Sync is unavailable; Tero will retry automatically."
            }
        }
    }
    private func checkOwner(_ identity: UUID, expected: UUID) throws {
        guard !Task.isCancelled, generation == expected, AccountStore.shared.user?.id == identity else { throw CancellationError() }
    }
}
