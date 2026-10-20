import AppKit
import Foundation

final class AuthMockState: @unchecked Sendable {
    let lock = NSLock()
    private var value = "normal"
    private var seen: [URLRequest] = []
    func mode(_ mode: String) { lock.lock(); defer { lock.unlock() }; value = mode; seen = [] }
    func receive(_ request: URLRequest) -> String { lock.lock(); defer { lock.unlock() }; seen.append(request); return value }
    func requests() -> [URLRequest] { lock.lock(); defer { lock.unlock() }; return seen }
}

final class AuthMockProtocol: URLProtocol, @unchecked Sendable {
    static let state = AuthMockState()
    static let userID = "11111111-1111-4111-8111-111111111111"
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let mode = Self.state.receive(request)
        if mode == "offline" {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
        }
        var status = 200
        var object: [String: Any] = [:]
        switch request.url!.lastPathComponent {
        case "settings": object = ["external": ["google": true, "github": true, "apple": false, "email": true]]
        case "token":
            object = ["access_token": "synthetic-access", "refresh_token": "synthetic-rotated", "expires_in": 3600, "token_type": "bearer", "user": ["id": mode == "mismatch" ? "22222222-2222-4222-8222-222222222222" : Self.userID, "email": "fixture@example.invalid"], "provider_token": "must-not-persist"]
            if mode == "expired" { status = 400; object = ["error_code": "refresh_token_not_found", "msg": "sensitive provider text"] }
            if mode == "rate" { status = 429; object = ["msg": "sensitive provider text"] }
        case "request": object = ["ticket": String(repeating: "t", count: 64)]
        case "exchange":
            object = ["access_token": "synthetic-new-access", "refresh_token": "synthetic-new-refresh", "expires_in": 3600, "token_type": "bearer", "user": ["id": "22222222-2222-4222-8222-222222222222", "email": "b@example.invalid"]]
            if mode == "confirmed-switch" { object["account_switch"] = true }
        case "user": object = ["id": Self.userID, "email": "fixture@example.invalid"]
        case "logout": status = 204
        default: status = 404
        }
        let data = status == 204 ? Data() : try! JSONSerialization.data(withJSONObject: object)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class AuthMemoryVault: AuthSessionStorage {
    var session: AuthSession?
    var failSave = false
    var failClear = false
    func read() throws -> AuthSession? { session }
    func save(_ session: AuthSession) throws { if failSave { throw AuthFailure.keychain }; self.session = session }
    func clear() throws { if failClear { throw AuthFailure.keychain }; session = nil }
}

@main struct AuthSmoke {
    @MainActor static func settle(_ store: AccountStore) async throws {
        for _ in 0..<200 {
            if !store.isBusy { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        fatalError("Auth state did not settle")
    }

    @MainActor static func main() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AuthMockProtocol.self]
        let client = AuthClient(projectURL: URL(string: "https://fixture.invalid")!, publicKey: "synthetic-public", transport: URLSession(configuration: config))
        if CommandLine.arguments.contains("--account-context-only") {
            let flow = try OAuthFlow(callbackURL: AuthConfiguration.callbackURL)
            let expected = UUID(uuidString: AuthMockProtocol.userID)!
            let url = try await client.accountWebsiteURL(token: "synthetic-access", flow: flow)
            precondition(url.host == "teroflow.app" && url.path == "/auth/account/entry")
            let request = AuthMockProtocol.state.requests().last!
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-access")
            precondition(!url.absoluteString.contains("synthetic-access") && !url.absoluteString.contains(flow.verifier))
            AuthMockProtocol.state.mode("unconfirmed-switch")
            do { _ = try await client.exchangeWebsite(ticket: String(repeating: "t", count: 43), verifier: flow.verifier, expectedUserID: expected); fatalError("Unconfirmed switch accepted") }
            catch AuthFailure.invalidSession { }
            precondition(AuthMockProtocol.state.requests().contains { $0.url?.lastPathComponent == "logout" })
            AuthMockProtocol.state.mode("confirmed-switch")
            let switched = try await client.exchangeWebsite(ticket: String(repeating: "t", count: 43), verifier: flow.verifier, expectedUserID: expected)
            precondition(switched.user.id != expected)
            let vault = AuthMemoryVault()
            vault.session = AuthSession(accessToken: "synthetic-old", refreshToken: "synthetic-old", expiresAt: .now.addingTimeInterval(3600), user: .init(id: expected, email: "a@example.invalid"))
            var opened: [URL] = []
            let store = AccountStore(client: client, vault: vault, openWebsite: { opened.append($0); return true })
            AuthMockProtocol.state.mode("normal")
            store.prepare(); try await settle(store)
            store.openBilling(); try await settle(store)
            precondition(opened.count == 1 && store.isSigningIn && store.user?.id == expected)
            store.prepare(); precondition(store.isSigningIn)
            AuthMockProtocol.state.mode("confirmed-switch")
            precondition(store.receiveCallback(URL(string: "com.aymenkadri.tero.dev://auth/callback?ticket=" + String(repeating: "t", count: 43))!))
            try await settle(store)
            precondition(store.user?.id == switched.user.id && vault.session?.user.id == switched.user.id && !store.isSigningIn)
            print("PASS: secure account URL, unconfirmed switch revoked, explicit switch accepted, refresh preserves pending flow and callback replaces the Mac session")
            return
        }
        if CommandLine.arguments.contains("--default-browser-only") {
            var opened: [URL] = []
            let browserStore = AccountStore(client: client, vault: AuthMemoryVault(), openWebsite: {opened.append($0); return true})
            browserStore.signIn()
            precondition(browserStore.isSigningIn && browserStore.isBusy && opened.count == 1)
            precondition(opened[0].host == "teroflow.app" && opened[0].path == "/login")
            let query = URLComponents(url: opened[0], resolvingAgainstBaseURL: false)!.queryItems!
            precondition(query.contains {$0.name == "desktop_challenge" && $0.value?.count == 43})
            precondition(!query.contains {$0.name == "code_verifier"})
            browserStore.signIn(); precondition(opened.count == 1)
            precondition(!browserStore.receiveCallback(URL(string: "https://evil.invalid/auth/callback?code=fixture")!))
            browserStore.cancelSignIn()
            precondition(!browserStore.isBusy && !browserStore.isSigningIn)
            precondition(!browserStore.receiveCallback(URL(string: "com.aymenkadri.tero.dev://auth/callback?code=fixture")!))
            let failed = AccountStore(client: client, vault: AuthMemoryVault(), openWebsite: {_ in false})
            failed.signIn(); precondition(!failed.isBusy && !failed.isSigningIn && failed.message != nil)
            print("PASS: default browser launch, duplicate guard, URL policy, cancellation and launch failure")
            return
        }
        AuthMockProtocol.state.mode("normal")
        let providers = try await client.providers()
        precondition(providers == [.google, .github])
        let session = try await client.exchange(code: "synthetic-code", verifier: "synthetic-verifier")
        precondition(session.refreshToken == "synthetic-rotated")
        let saved = String(decoding: try JSONEncoder().encode(session), as: UTF8.self)
        precondition(!saved.contains("provider_token") && !saved.contains("must-not-persist"))
        _ = try await client.validate(session)
        _ = try await client.refresh(session)
        try await client.signOut(session)
        let requests = AuthMockProtocol.state.requests()
        precondition(requests.allSatisfy { $0.value(forHTTPHeaderField: "apikey") == "synthetic-public" })
        precondition(requests.last!.url!.query == "scope=local")
        precondition(requests.last!.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-access")
        precondition(requests.contains { $0.url?.query == "grant_type=pkce" })
        precondition(requests.contains { $0.url?.query == "grant_type=refresh_token" })

        AuthMockProtocol.state.mode("mismatch")
        do { _ = try await client.refresh(session); fatalError("Cross-user refresh accepted") }
        catch AuthFailure.invalidSession {}
        AuthMockProtocol.state.mode("rate")
        do { _ = try await client.refresh(session); fatalError("Rate limit ignored") }
        catch AuthFailure.rateLimited {}

        let vault = AuthMemoryVault()
        vault.session = AuthSession(accessToken: "old", refreshToken: "old", expiresAt: .distantPast, user: session.user)
        let store = AccountStore(client: client, vault: vault)
        AuthMockProtocol.state.mode("offline")
        store.prepare(); try await settle(store)
        precondition(vault.session != nil && store.user != nil && !store.verified)
        AuthMockProtocol.state.mode("normal")
        store.prepare(); try await settle(store)
        precondition(store.verified && vault.session?.refreshToken == "synthetic-rotated")
        vault.failClear = true
        store.signOut()
        precondition(store.user != nil && vault.session != nil)
        vault.failClear = false
        store.signOut(); try await settle(store)
        precondition(store.user == nil && vault.session == nil)

        vault.session = AuthSession(accessToken: "old", refreshToken: "old", expiresAt: .distantPast, user: session.user)
        let expired = AccountStore(client: client, vault: vault)
        AuthMockProtocol.state.mode("expired")
        expired.prepare(); try await settle(expired)
        precondition(expired.user == nil && vault.session == nil)
        precondition(expired.message == AuthFailure.expiredSession.localizedDescription)
        print("PASS: provider filtering, exchange, refresh, user validation, local logout, no provider-token persistence, cross-user rejection, rate limit, offline preservation, Keychain failure, session expiry")
    }
}
