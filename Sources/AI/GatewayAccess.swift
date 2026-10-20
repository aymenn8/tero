import Foundation

@MainActor
enum GatewayAccess {
    /// The person's own AI key takes priority; Tero Pro is the optional managed alternative.
    /// Nil means no AI is set up yet.
    static func credential() async -> String? {
        if usesOwnKey { return CorrectionClient.ownKeyCredential }
        // Signed-in accounts use Tero Pro; the server enforces the subscription.
        return try? await AccountStore.shared.accessToken()
    }
    static var usesOwnKey: Bool { AIConfiguration.active != nil }
    static func event(_ event: String, mode: String? = nil) {
        Task {
            guard let token = try? await AccountStore.shared.accessToken() else { return }
            let os = ProcessInfo.processInfo.operatingSystemVersion
            let body: [String: Any] = ["id": UUID().uuidString, "event": event, "mode": mode as Any? ?? NSNull(),
                "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.1",
                "os": "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"]
            var request = URLRequest(url: AuthConfiguration.projectURL.appendingPathComponent("functions/v1/tero-events"))
            request.httpMethod = "POST"; request.timeoutInterval = 5
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            _ = try? await URLSession.shared.data(for: request)
        }
    }
    static func didRequest() {
        guard !usesOwnKey, AccountStore.shared.user != nil else { return }
        Task { await AccountStore.shared.refreshUsage() }
    }
}
