/// Which screen the app starts from. Without a device key it is always role selection,
/// so a 401 (which clears the key) sends the person back there.
public enum AppRoute: Hashable, Sendable {
    case chooseRole
    case protectedHome
    case familyHome

    public init(_ credentials: Credentials?) {
        switch credentials?.role {
        case nil: self = .chooseRole
        case .protected: self = .protectedHome
        case .family: self = .familyHome
        }
    }
}
