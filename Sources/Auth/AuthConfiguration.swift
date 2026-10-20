import Foundation

/// Public client configuration only. Never place a service-role key here.
enum AuthConfiguration {
    static let projectURL = URL(string: "https://ufcsajujaqemlduvpjpi.supabase.co")!
    static let publishableKey = "sb_publishable_oO1lZhIrGhCSFS0--kzEsQ_OF9n3kOV"
    static let callbackURL = URL(string: "\(Bundle.main.bundleIdentifier ?? "com.aymenkadri.tero.dev")://auth/callback")!
    static var websiteOrigin: URL? {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "TeroWebsiteURL") as? String,
           let url = URL(string: raw), url.scheme == "https", url.host != nil,
           url.user == nil, url.password == nil { return url }
        return URL(string: "https://teroflow.app")
    }
}
