import Foundation
import Security

protocol AuthSessionStorage {
    func read() throws -> AuthSession?
    func save(_ session: AuthSession) throws
    func clear() throws
}

struct AuthSessionVault: AuthSessionStorage {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "\(Bundle.main.bundleIdentifier ?? "com.aymenkadri.tero.dev").auth",
         kSecAttrAccount as String: "ufcsajujaqemlduvpjpi.session"]
    }

    func read() throws -> AuthSession? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw AuthFailure.keychain }
        guard let session = try? JSONDecoder().decode(AuthSession.self, from: data), session.isValid else {
            throw AuthFailure.invalidSession
        }
        return session
    }

    func save(_ session: AuthSession) throws {
        guard session.isValid else { throw AuthFailure.invalidSession }
        let values = [kSecValueData as String: try JSONEncoder().encode(session)]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw AuthFailure.keychain }
        var attributes = query.merging(values) { _, new in new }
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else { throw AuthFailure.keychain }
    }

    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AuthFailure.keychain }
    }
}
