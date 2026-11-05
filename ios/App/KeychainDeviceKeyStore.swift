import Foundation
import MimamoriCore
import Security

/// Keeps `Credentials` (the device key and role) in the Keychain, readable after the first unlock
/// so a background push can still call the API. Never log what is stored here.
///
/// The item lives in the app group's keychain access group, so the Safari extension can send its page
/// check with the same key (ios/SafariExtension). Apple: "You can use app group names as keychain
/// access group names, without adding them to the Keychain access groups entitlement" (Sharing access
/// to keychain items among a collection of apps). Builds before task 9 saved the item in the app's
/// private group; `load()` moves such an item over the first time the app reads it.
///
/// Compiled into both the App and the SafariExtension targets (ios/project.yml).
struct KeychainDeviceKeyStore: DeviceKeyStore {
  enum Failure: Error { case status(OSStatus) }

  static let sharedAccessGroup = "group.com.sagochiko.mimamori"

  private let service: String
  private let account: String

  /// Tests pass their own service name so the app's real item is left alone.
  init(service: String = "com.sagochiko.mimamori.device", account: String = "credentials") {
    self.service = service
    self.account = account
  }

  /// Without an access group, so a lookup or delete covers every group this process can reach.
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
    lookup[kSecReturnAttributes as String] = true
    lookup[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    guard SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess,
      let found = item as? [String: Any],
      let data = found[kSecValueData as String] as? Data,
      let credentials = try? JSONDecoder().decode(Credentials.self, from: data)
    else { return nil }
    if let group = found[kSecAttrAccessGroup as String] as? String, group != Self.sharedAccessGroup {
      moveToSharedGroup(data, from: group)
    }
    return credentials
  }

  /// An item from before task 9. Added in the shared group first (the group is part of the item's
  /// identity, so the two do not collide), and the old one deleted only after that worked.
  private func moveToSharedGroup(_ data: Data, from group: String) {
    var item = query
    item[kSecAttrAccessGroup as String] = Self.sharedAccessGroup
    item[kSecValueData as String] = data
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let status = SecItemAdd(item as CFDictionary, nil)
    // A duplicate is a move that added the new item before and did not get to delete the old one.
    guard status == errSecSuccess || status == errSecDuplicateItem else { return }
    var old = query
    old[kSecAttrAccessGroup as String] = group
    SecItemDelete(old as CFDictionary)
  }

  func save(_ credentials: Credentials) throws {
    let data = try JSONEncoder().encode(credentials)
    var item = query
    item[kSecAttrAccessGroup as String] = Self.sharedAccessGroup
    item[kSecValueData as String] = data
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    clear()
    var status = SecItemAdd(item as CFDictionary, nil)
    if status == errSecMissingEntitlement {
      // A build signed without the app group: keep joining working as before task 9. The Safari
      // extension then finds no key and draws no warning.
      item.removeValue(forKey: kSecAttrAccessGroup as String)
      status = SecItemAdd(item as CFDictionary, nil)
    }
    guard status == errSecSuccess else { throw Failure.status(status) }
  }

  func clear() {
    SecItemDelete(query as CFDictionary)
  }
}
