import Foundation
import Security

/// Private development gateway credential, never the OpenAI API key.
enum GatewayCredential {
  private static var query: [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: "com.aymenkadri.tero.dev.gateway",
     kSecAttrAccount as String: "private-tester"]
  }

  static func read() -> String? {
    var attributes = query
    attributes[kSecReturnData as String] = true
    attributes[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    guard SecItemCopyMatching(attributes as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func save(_ token: String) -> Bool {
    guard token.count >= 40, token.count <= 128, !token.contains("\n") else { return false }
    let value = [kSecValueData as String: Data(token.utf8)]
    let status = SecItemUpdate(query as CFDictionary, value as CFDictionary)
    if status == errSecSuccess { return true }
    guard status == errSecItemNotFound else { return false }
    var attributes = query.merging(value) { _, new in new }
    attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
  }
}
