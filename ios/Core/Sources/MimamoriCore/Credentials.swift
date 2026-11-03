import Foundation

/// What this device keeps after joining a family. The App stores it in the Keychain.
public struct Credentials: Codable, Hashable, Sendable {
    public let deviceKey: String
    public let memberId: String
    public let familyId: String
    public let role: Role
    /// Only `POST /families` returns it. Goes into the SMS and DNS endpoints; never log it.
    public let familyToken: String?

    public init(deviceKey: String, memberId: String, familyId: String, role: Role, familyToken: String? = nil) {
        self.deviceKey = deviceKey
        self.memberId = memberId
        self.familyId = familyId
        self.role = role
        self.familyToken = familyToken
    }
}

/// Where the device key lives. The App implements it with the Keychain; tests use `InMemoryDeviceKeyStore`.
public protocol DeviceKeyStore: Sendable {
    func load() -> Credentials?
    func save(_ credentials: Credentials) throws
    func clear()
}

public final class InMemoryDeviceKeyStore: DeviceKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Credentials?

    public init(_ credentials: Credentials? = nil) {
        stored = credentials
    }

    public func load() -> Credentials? { lock.withLock { stored } }
    public func save(_ credentials: Credentials) { lock.withLock { stored = credentials } }
    public func clear() { lock.withLock { stored = nil } }
}
