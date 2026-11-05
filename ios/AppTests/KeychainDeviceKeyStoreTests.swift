import Foundation
import MimamoriCore
import Security
import Testing

@testable import Mimamori

/// The device key in the Keychain (#16). It moved to the app group's access group so the Safari
/// extension can read it; joining must keep working, and a key saved by an earlier build must move over.
/// Runs inside the app on the simulator, with the app's own entitlements. Uses its own service name so
/// the app's real item is not touched.
@Suite(.serialized)
struct KeychainDeviceKeyStoreTests {
  private let service = "com.sagochiko.mimamori.device.test"
  private let account = "credentials"
  private let credentials = Credentials(
    deviceKey: "dk_test_keychain", memberId: "m-1", familyId: "f-1", role: .protected
  )

  private var store: KeychainDeviceKeyStore {
    KeychainDeviceKeyStore(service: service, account: account)
  }

  /// The access group of the stored item, or nil when there is none.
  private func storedGroup() -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnAttributes as String: true,
      kSecMatchLimit as String: kSecMatchLimitAll,
    ]
    var items: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &items) == errSecSuccess,
      let list = items as? [[String: Any]], list.count == 1
    else { return nil }
    return list[0][kSecAttrAccessGroup as String] as? String
  }

  @Test("保存した鍵を読み戻せ、拡張と共有する場所に入る")
  func saveLoad() throws {
    store.clear()
    defer { store.clear() }
    try store.save(credentials)
    #expect(store.load() == credentials)
    #expect(storedGroup() == KeychainDeviceKeyStore.sharedAccessGroup)
  }

  @Test("前の版がアプリだけの場所に置いた鍵は、読んだときに共有の場所へ移る")
  func movesOldItem() throws {
    store.clear()
    defer { store.clear() }
    // As builds before task 9 saved it: no access group, so the app's default group.
    let old: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecValueData as String: try JSONEncoder().encode(credentials),
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    #expect(SecItemAdd(old as CFDictionary, nil) == errSecSuccess)
    #expect(storedGroup() != KeychainDeviceKeyStore.sharedAccessGroup)

    #expect(store.load() == credentials)
    #expect(storedGroup() == KeychainDeviceKeyStore.sharedAccessGroup)
    #expect(store.load() == credentials)
  }

  @Test("消すと読めなくなる")
  func clear() throws {
    try store.save(credentials)
    store.clear()
    #expect(store.load() == nil)
  }
}
