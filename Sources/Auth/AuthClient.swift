import Foundation

struct AuthClient: Sendable {
    let projectURL: URL
    let publicKey: String
    let transport: URLSession

    init(projectURL: URL = AuthConfiguration.projectURL,
         publicKey: String = AuthConfiguration.publishableKey, transport: URLSession? = nil) {
        self.projectURL = projectURL
        self.publicKey = publicKey
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        self.transport = transport ?? URLSession(configuration: configuration)
    }

    func providers() async throws -> Set<AuthProvider> {
        struct Settings: Decodable { let external: [String: Bool] }
        let data = try await request(path: "settings")
        let settings = try JSONDecoder().decode(Settings.self, from: data)
        return Set(AuthProvider.allCases.filter { settings.external[$0.rawValue] == true })
    }

    func exchange(code: String, verifier: String) async throws -> AuthSession {
        try await token(grant: "pkce", body: ["auth_code": code, "code_verifier": verifier])
    }

    func exchangeWebsite(ticket: String, verifier: String, expectedUserID: UUID? = nil) async throws -> AuthSession {
        guard let origin = AuthConfiguration.websiteOrigin else { throw AuthFailure.unavailable }
        var request = URLRequest(url: origin.appendingPathComponent("auth/desktop/exchange"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["ticket": ticket, "verifier": verifier])
        let (data, response) = try await transport.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              data.count <= 256 * 1024 else { throw AuthFailure.invalidSession }
        let session = try decodeSession(data)
        struct Consent: Decodable { let account_switch: Bool? }
        if let expectedUserID, session.user.id != expectedUserID,
           (try? JSONDecoder().decode(Consent.self, from: data))?.account_switch != true {
            try? await signOut(session)
            throw AuthFailure.invalidSession
        }
        return session
    }

    func accountWebsiteURL(token: String, flow: OAuthFlow) async throws -> URL {
        guard let origin = AuthConfiguration.websiteOrigin, let channel = flow.callbackURL.scheme else { throw AuthFailure.unavailable }
        var request = URLRequest(url: origin.appendingPathComponent("auth/account/request"))
        request.httpMethod = "POST"
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["challenge": flow.challenge, "channel": channel])
        let (data, response) = try await transport.data(for: request)
        try Task.checkCancellation()
        struct Ticket: Decodable { let ticket: String }
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 4096,
              let ticket = try? JSONDecoder().decode(Ticket.self, from: data),
              ticket.ticket.range(of: "^[A-Za-z0-9_-]{40,2048}$", options: .regularExpression) != nil else { throw AuthFailure.unavailable }
        var url = URLComponents(url: origin.appendingPathComponent("auth/account/entry"), resolvingAgainstBaseURL: false)!
        url.queryItems = [.init(name: "ticket", value: ticket.ticket)]
        return url.url!
    }

    func refresh(_ session: AuthSession) async throws -> AuthSession {
        let refreshed = try await token(grant: "refresh_token", body: ["refresh_token": session.refreshToken])
        guard refreshed.user.id == session.user.id else { throw AuthFailure.invalidSession }
        return refreshed
    }

    func validate(_ session: AuthSession) async throws -> AuthSession.User {
        let data = try await request(path: "user", bearer: session.accessToken)
        let user = try JSONDecoder().decode(AuthSession.User.self, from: data)
        guard user.id == session.user.id else { throw AuthFailure.invalidSession }
        return user
    }

    func signOut(_ session: AuthSession) async throws {
        _ = try await request(path: "logout", query: [.init(name: "scope", value: "local")],
                              method: "POST", bearer: session.accessToken)
    }

    func submitFeedback(id: UUID, category: String, description: String, diagnostics: Bool, bearer: String) async throws {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ["bug", "idea", "other"].contains(category), (10...8000).contains(trimmed.count) else { throw AuthFailure.unavailable }
        var request = URLRequest(url: projectURL.appendingPathComponent("rest/v1/rpc/submit_feedback"))
        request.httpMethod = "POST"
        request.setValue(publicKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        var body = ["p_id": id.uuidString, "p_category": category, "p_description": trimmed]
        if diagnostics {
            body["p_app_version"] = String((Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.1").prefix(40))
            body["p_os_version"] = String(ProcessInfo.processInfo.operatingSystemVersionString.prefix(100))
        }
        request.httpBody = try JSONEncoder().encode(body)
        let (feedbackData, response) = try await transport.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw AuthFailure.unavailable }
        if http.statusCode == 401 { throw AuthFailure.expiredSession }
        guard (200...299).contains(http.statusCode) else {
            struct APIError: Decodable { let code: String }
            let code = (try? JSONDecoder().decode(APIError.self, from: feedbackData))?.code ?? String(http.statusCode)
            throw FeedbackDeliveryError(code: code.range(of: "^[A-Z0-9]{3,12}$", options: .regularExpression) != nil ? code : String(http.statusCode))
        }
    }

    private func token(grant: String, body: [String: String]) async throws -> AuthSession {
        let data = try await request(path: "token", query: [.init(name: "grant_type", value: grant)],
                                     method: "POST", body: body)
        return try decodeSession(data)
    }

    private func decodeSession(_ data: Data) throws -> AuthSession {
        struct Response: Decodable {
            let access_token: String
            let refresh_token: String
            let expires_in: Double
            let token_type: String
            let user: AuthSession.User
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.token_type.lowercased() == "bearer", response.expires_in > 0,
              response.expires_in.isFinite, response.expires_in <= 604_800 else { throw AuthFailure.invalidSession }
        let result = AuthSession(accessToken: response.access_token, refreshToken: response.refresh_token,
                                 expiresAt: Date().addingTimeInterval(response.expires_in), user: response.user)
        guard result.isValid else { throw AuthFailure.invalidSession }
        return result
    }

    private func request(path: String, query: [URLQueryItem] = [], method: String = "GET",
                         body: [String: String]? = nil, bearer: String? = nil) async throws -> Data {
        var components = URLComponents(url: projectURL.appendingPathComponent("auth/v1/\(path)"), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue(publicKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await transport.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, data.count <= 256 * 1024 else { throw AuthFailure.unavailable }
        if http.statusCode == 429 { throw AuthFailure.rateLimited }
        guard (200..<300).contains(http.statusCode) else {
            struct Failure: Decodable { let error_code: String? }
            let code = (try? JSONDecoder().decode(Failure.self, from: data))?.error_code
            let invalidRefresh = ["refresh_token_not_found", "refresh_token_already_used", "session_not_found", "session_expired"]
            if http.statusCode == 401 || invalidRefresh.contains(code ?? "") { throw AuthFailure.expiredSession }
            throw AuthFailure.unavailable
        }
        return data
    }
}

struct FeedbackDeliveryError: LocalizedError {
    let code: String
    var errorDescription: String? { "Couldn't send your feedback (\(code)). Please try again." }
}
