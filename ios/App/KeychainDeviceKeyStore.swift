import Foundation
import MimamoriCore
import Security

/// Keeps `Credentials` (the device key and role) in the Keychain, readable after the first unlock
/// so a background push can still call the API. Never log what is stored here.
struct KeychainDeviceKeyStore: DeviceKeyStore {
  enum Failure: Error { case status(OSStatus) }

  private let service = "com.sagochiko.mimamori.device"
  private let account = "credentials"

  private var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }

  func load() -> Credentials? {
    var lookup = query
    lookup[kSecReturnData as String] = true
    lookup[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    guard SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data
    else { return nil }
    return try? JSONDecoder().decode(Credentials.self, from: data)
  }

  func save(_ credentials: Credentials) throws {
    let data = try JSONEncoder().encode(credentials)
    clear()
    var item = query
    item[kSecValueData as String] = data
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let status = SecItemAdd(item as CFDictionary, nil)
    guard status == errSecSuccess else { throw Failure.status(status) }
  }

  func clear() {
    SecItemDelete(query as CFDictionary)
  }
}
