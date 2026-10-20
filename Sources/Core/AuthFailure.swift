import Foundation

enum AuthFailure: Error, LocalizedError, Equatable {
    case invalidCallback, invalidSession, expiredSession, unavailable, rateLimited, keychain, random, providerDisabled

    var errorDescription: String? {
        switch self {
        case .invalidCallback: "Sign-in could not be completed. Please try again."
        case .invalidSession, .expiredSession: "Your session has expired. Please sign in again."
        case .unavailable: "Unable to connect. Please try again."
        case .rateLimited: "Too many attempts. Please try again in a moment."
        case .keychain: "Unable to access your session in Keychain. Unlock your Mac and try again."
        case .random: "Unable to start a secure sign-in. Please try again."
        case .providerDisabled: "This sign-in provider is not available yet."
        }
    }
}
