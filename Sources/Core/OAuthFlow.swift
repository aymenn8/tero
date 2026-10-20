import Foundation
import CryptoKit
import Security

/// The verifier exists only for this sign-in attempt. No implicit token callbacks.
struct OAuthFlow: Sendable {
    let verifier: String
    let callbackURL: URL

    init(callbackURL: URL) throws {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw AuthFailure.random
        }
        verifier = Self.base64URL(Data(bytes))
        self.callbackURL = callbackURL
    }

    init(verifier: String, callbackURL: URL) {
        self.verifier = verifier
        self.callbackURL = callbackURL
    }

    var challenge: String { Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))) }

    func websiteURL(origin: URL) throws -> URL {
        guard origin.user == nil, origin.password == nil, origin.query == nil, origin.fragment == nil,
              origin.scheme == "https" || (origin.scheme == "http" && origin.host == "localhost") else {
            throw AuthFailure.invalidCallback
        }
        var url = URLComponents(url: origin.appendingPathComponent("login"), resolvingAgainstBaseURL: false)!
        guard let scheme = callbackURL.scheme,
              ["com.aymenkadri.tero", "com.aymenkadri.tero.dev", "com.aymenkadri.tero.staging"].contains(scheme) else { throw AuthFailure.invalidCallback }
        url.queryItems = [.init(name: "desktop_challenge", value: challenge), .init(name: "desktop_scheme", value: scheme)]
        return url.url!
    }

    func authorizeURL(projectURL: URL, provider: AuthProvider) -> URL {
        var url = URLComponents(url: projectURL.appendingPathComponent("auth/v1/authorize"), resolvingAgainstBaseURL: false)!
        url.queryItems = [
            .init(name: "provider", value: provider.rawValue),
            .init(name: "redirect_to", value: callbackURL.absoluteString),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "s256")
        ]
        return url.url!
    }

    func code(from url: URL) throws -> String {
        guard url.scheme == callbackURL.scheme, url.host == callbackURL.host,
              url.path == callbackURL.path, url.port == nil, url.user == nil,
              url.password == nil, url.fragment == nil,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              !items.contains(where: { $0.name == "error" || $0.name == "error_code" || $0.name == "ticket" }),
              items.filter({ $0.name == "code" }).count == 1,
              let code = items.first(where: { $0.name == "code" })?.value,
              !code.isEmpty, code.utf8.count <= 2048 else { throw AuthFailure.invalidCallback }
        return code
    }

    func ticket(from url: URL) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems, items.count == 1,
              items[0].name == "ticket", let ticket = items[0].value,
              ticket.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else {
            throw AuthFailure.invalidCallback
        }
        var check = components
        check.queryItems = [.init(name: "code", value: ticket)]
        _ = try code(from: check.url!)
        return ticket
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
