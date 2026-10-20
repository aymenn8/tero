import Foundation
import AppKit
import Observation

@MainActor @Observable
final class AccountStore: NSObject {
    static let shared = AccountStore()
    private(set) var usage: AccountUsage?
    @ObservationIgnored private var refreshTask: Task<AuthSession, Error>?
    private(set) var user: AuthSession.User?
    private(set) var isBusy = false
    private(set) var isSigningIn = false
    private(set) var message: String?
    private(set) var verified = false
    @ObservationIgnored private let client: AuthClient
    @ObservationIgnored private let vault: any AuthSessionStorage
    @ObservationIgnored private var session: AuthSession?
    @ObservationIgnored private let openWebsite: (URL) -> Bool
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var pendingFlow: OAuthFlow?
    @ObservationIgnored private var accountSwitchUserID: UUID?
    @ObservationIgnored private var pendingSince: Date?
    @ObservationIgnored private var signInExpiry: Task<Void, Never>?

    init(client: AuthClient = AuthClient(), vault: any AuthSessionStorage = AuthSessionVault(),
         openWebsite: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        self.client = client
        self.vault = vault
        self.openWebsite = openWebsite
    }

    func prepare() {
        guard !isBusy, !isSigningIn else { return }
        let id = begin()
        task = Task { [weak self] in
            guard let self else { return }
            defer { finish(id) }
            do {
                if session == nil { session = try vault.read(); user = session?.user }
                if let existing = session {
                    let current: AuthSession
                    if existing.needsRefresh() {
                        _ = try await accessToken()
                        guard let refreshed = session else { throw AuthFailure.expiredSession }
                        current = refreshed
                    } else {
                        do { _ = try await client.validate(existing); current = existing }
                        catch AuthFailure.expiredSession {
                            let refreshed = try await client.refresh(existing)
                            current = refreshed
                        }
                    }
                    guard generation == id else { return }
                    try vault.save(current)
                    session = current; user = current.user; verified = true
                    TextHabitStore.shared.refreshOwner()
                    await refreshUsage()
                }
            } catch {
                guard generation == id else { return }
                if error as? AuthFailure == .expiredSession || error as? AuthFailure == .invalidSession {
                    do { try vault.clear(); session = nil; user = nil; TextHabitStore.shared.refreshOwner() }
                    catch { message = AuthFailure.keychain.localizedDescription; return }
                }
                verified = false
                message = safeMessage(error)
            }
        }
    }

    func signIn() {
        guard !isBusy, user == nil else { return }
        guard let origin = AuthConfiguration.websiteOrigin else {
            message = "Website sign-in is not configured for this build."; return
        }
        do {
            let flow = try OAuthFlow(callbackURL: AuthConfiguration.callbackURL)
            let website = try flow.websiteURL(origin: origin)
            let id = begin()
            pendingFlow = flow
            pendingSince = .now
            isSigningIn = true
            signInExpiry = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(600)) } catch { return }
                guard let self, generation == id, isSigningIn else { return }
                cancelSignIn()
                message = "This connection expired. Start sign-in again."
            }
            // LaunchServices uses the user's default browser. The verifier stays in memory;
            // the registered URL callback returns through AppDelegate to receiveCallback.
            if !openWebsite(website) { message = AuthFailure.unavailable.localizedDescription; finish(id) }
        } catch { message = safeMessage(error) }
    }

    private func complete(url: URL, flow: OAuthFlow, id: UUID) {
        guard generation == id, let since = pendingSince, Date().timeIntervalSince(since) < 600 else {
            message = "This connection expired. Start sign-in again."; finish(id); return
        }
        signInExpiry?.cancel(); signInExpiry = nil
        pendingFlow = nil; pendingSince = nil
        isBusy = true
        task = Task { [weak self] in
            guard let self else { return }
            defer { finish(id) }
            do {
                let result: AuthSession
                if let ticket = try? flow.ticket(from: url) {
                    result = try await client.exchangeWebsite(ticket: ticket, verifier: flow.verifier, expectedUserID: accountSwitchUserID)
                } else {
                    guard accountSwitchUserID == nil else { throw AuthFailure.invalidCallback }
                    let code = try flow.code(from: url)
                    result = try await client.exchange(code: code, verifier: flow.verifier)
                }
                guard generation == id else { return }
                let previous = session
                do { try vault.save(result) }
                catch {
                    try? await client.signOut(result)
                    throw AuthFailure.keychain
                }
                session = result; user = result.user; verified = true
                TextHabitStore.shared.refreshOwner()
                usage = nil
                if let previous, previous.user.id != result.user.id { try? await client.signOut(previous) }
                await refreshUsage()
            } catch {
                guard generation == id else { return }
                message = safeMessage(error)
            }
        }
    }

    func signOut() {
        guard !isBusy else { return }
        let previous = session
        refreshTask?.cancel(); refreshTask = nil
        do { try vault.clear() }
        catch { message = AuthFailure.keychain.localizedDescription; return }
        session = nil; user = nil; verified = false; usage = nil
        TextHabitStore.shared.refreshOwner()
        let id = begin()
        task = Task { [weak self] in
            guard let self else { return }
            defer { finish(id) }
            if let previous {
                do {
                    let current = previous.needsRefresh() ? try await client.refresh(previous) : previous
                    try await client.signOut(current)
                } catch AuthFailure.expiredSession { /* Session is already invalid. */ }
                catch {
                    guard generation == id else { return }
                    message = "Signed out on this Mac. The server could not confirm session revocation."
                }
            }
        }
    }

    func cancelSignIn() {
        guard isSigningIn else { return }
        generation = UUID()
        signInExpiry?.cancel(); signInExpiry = nil
        pendingFlow = nil; pendingSince = nil; accountSwitchUserID = nil
        task?.cancel(); task = nil
        isBusy = false; isSigningIn = false; message = nil
    }

    /// Browser sign-in returns through the registered app URL scheme.
    /// Only a live attempt with its original verifier can consume a callback.
    func receiveCallback(_ url: URL) -> Bool {
        guard isSigningIn, let flow = pendingFlow, let since = pendingSince,
              Date().timeIntervalSince(since) < 600,
              (try? flow.code(from: url)) != nil || (try? flow.ticket(from: url)) != nil else { return false }
        complete(url: url, flow: flow, id: generation)
        return true
    }

    /// One refresh at a time across ranking, AI and account UI; no credentials leave Keychain/network memory.
    func accessToken() async throws -> String? {
        if session == nil { session = try vault.read(); user = session?.user }
        guard let existing = session else { return nil }
        if existing.needsRefresh() {
            let expected = generation
            if refreshTask == nil { refreshTask = Task { try await client.refresh(existing) } }
            let updated: AuthSession
            do { updated = try await refreshTask!.value } catch { refreshTask = nil; throw error }
            refreshTask = nil
            guard generation == expected, session?.user.id == existing.user.id else { throw AuthFailure.expiredSession }
            try vault.save(updated); session = updated; user = updated.user
        }
        return session?.accessToken
    }

    func submitFeedback(id: UUID, category: String, description: String, diagnostics: Bool) async throws {
        guard let token = try await accessToken() else { throw AuthFailure.expiredSession }
        try await client.submitFeedback(id: id, category: category, description: description, diagnostics: diagnostics, bearer: token)
    }

    func refreshUsage() async {
        do {
            guard let token = try await accessToken(), let identity = user?.id else { usage = nil; return }
            var request = URLRequest(url: AuthConfiguration.projectURL.appendingPathComponent("functions/v1/tero-account"))
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 10
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 8192, user?.id == identity else { return }
            usage = try JSONDecoder().decode(AccountUsage.self, from: data)
        } catch { /* Keep the last server snapshot; the gateway remains authoritative. */ }
    }

    func openBilling() {
        guard !isBusy, let origin = AuthConfiguration.websiteOrigin else { return }
        guard let user else { _ = openWebsite(origin.appendingPathComponent("login")); return }
        let expectedID = user.id
        let id = begin()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                guard let token = try await accessToken() else { throw AuthFailure.expiredSession }
                let flow = try OAuthFlow(callbackURL: AuthConfiguration.callbackURL)
                let url = try await client.accountWebsiteURL(token: token, flow: flow)
                guard !Task.isCancelled, generation == id, self.user?.id == expectedID else { return }
                pendingFlow = flow; pendingSince = .now
                accountSwitchUserID = expectedID; isSigningIn = true
                isBusy = false; task = nil
                // Keep the original Mac account until a confirmed, verifier-bound switch returns.
                signInExpiry?.cancel()
                signInExpiry = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(600)) } catch { return }
                    guard let self, generation == id else { return }
                    finish(id)
                }
                if !openWebsite(url) { message = AuthFailure.unavailable.localizedDescription; finish(id) }
            } catch {
                guard generation == id else { return }
                message = "Couldn't open your account securely. Try again."
                finish(id)
            }
        }
    }

    private func begin() -> UUID {
        signInExpiry?.cancel(); signInExpiry = nil
        pendingFlow = nil; pendingSince = nil; accountSwitchUserID = nil; isSigningIn = false
        generation = UUID(); message = nil; isBusy = true
        return generation
    }

    private func finish(_ id: UUID) {
        guard generation == id else { return }
        signInExpiry?.cancel(); signInExpiry = nil
        isBusy = false; isSigningIn = false; task = nil
        pendingFlow = nil; pendingSince = nil; accountSwitchUserID = nil
    }

    private func safeMessage(_ error: Error) -> String {
        (error as? AuthFailure)?.localizedDescription ?? AuthFailure.unavailable.localizedDescription
    }
}
