import XCTest
@testable import TeroCore

final class OAuthFlowTests: XCTestCase {
    let callback = URL(string: "com.aymenkadri.tero.dev://auth/callback")!

    func testNativeTicketRejectsMixedOrUnrelatedCallbacks() throws {
        let flow = try OAuthFlow(callbackURL: callback)
        let ticket = String(repeating: "a", count: 43)
        let valid = URL(string: callback.absoluteString + "?ticket=" + ticket)!
        XCTAssertEqual(try flow.ticket(from: valid), ticket)
        XCTAssertThrowsError(try flow.code(from: valid))
        for value in [valid.absoluteString + "&code=x", valid.absoluteString + "&ticket=" + ticket,
                      callback.absoluteString + "?ticket=short", "https://auth/callback?ticket=" + ticket] {
            XCTAssertThrowsError(try flow.ticket(from: URL(string: value)!))
        }
    }

    func testPKCERFC7636Vector() {
        let flow = OAuthFlow(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", callbackURL: callback)
        XCTAssertEqual(flow.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testRandomFlowsUseDifferentVerifiersAndNoPadding() throws {
        let a = try OAuthFlow(callbackURL: callback)
        let b = try OAuthFlow(callbackURL: callback)
        XCTAssertEqual(a.verifier.count, 43)
        XCTAssertNotEqual(a.verifier, b.verifier)
        XCTAssertFalse(a.verifier.contains("="))
    }

    func testOnlyExactCodeCallbackAccepted() throws {
        let flow = try OAuthFlow(callbackURL: callback)
        XCTAssertEqual(try flow.code(from: URL(string: callback.absoluteString + "?code=synthetic")!), "synthetic")
        for value in [
            "https://auth/callback?code=x", "com.aymenkadri.tero.dev://other/callback?code=x",
            "com.aymenkadri.tero.dev://auth/other?code=x", callback.absoluteString + "?code=",
            callback.absoluteString + "?code=a&code=b", callback.absoluteString + "?code=a&error=denied",
            callback.absoluteString + "#access_token=x", callback.absoluteString + "?code=a#token=x",
            "com.aymenkadri.tero.dev://user@auth/callback?code=x",
            "com.aymenkadri.tero.dev://auth:42/callback?code=x"
        ] { XCTAssertThrowsError(try flow.code(from: URL(string: value)!)) }
    }

    func testAuthorizationDoesNotLeakVerifierAndUsesPKCE() throws {
        let flow = try OAuthFlow(callbackURL: callback)
        let url = flow.authorizeURL(projectURL: URL(string: "https://example.supabase.co")!, provider: .github)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "provider" }?.value, "github")
        XCTAssertEqual(items.first { $0.name == "code_challenge_method" }?.value, "s256")
        XCTAssertEqual(items.first { $0.name == "redirect_to" }?.value, callback.absoluteString)
        XCTAssertFalse(url.absoluteString.contains(flow.verifier))
        XCTAssertFalse(url.absoluteString.contains("access_token"))
    }

    func testSessionRefreshBeforeExpiry() {
        let now = Date()
        let session = AuthSession(accessToken: "synthetic", refreshToken: "synthetic", expiresAt: now.addingTimeInterval(59), user: .init(id: UUID(), email: nil))
        XCTAssertTrue(session.needsRefresh(at: now))
        XCTAssertFalse(session.needsRefresh(at: now.addingTimeInterval(-120)))
    }

    func testWebsiteReceivesOnlyChallengeAndDisallowsInsecureRemoteHost() throws {
        let flow = try OAuthFlow(callbackURL: callback)
        let url = try flow.websiteURL(origin: URL(string: "http://localhost:3000")!)
        XCTAssertEqual(url.path, "/login")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                       [URLQueryItem(name: "desktop_challenge", value: flow.challenge), URLQueryItem(name: "desktop_scheme", value: "com.aymenkadri.tero.dev")])
        XCTAssertFalse(url.absoluteString.contains(flow.verifier))
        XCTAssertThrowsError(try flow.websiteURL(origin: URL(string: "http://example.com")!))
        XCTAssertThrowsError(try flow.websiteURL(origin: URL(string: "https://user@example.com")!))
    }
}
