/// What the menu on a home screen offers, by role (#279).
///
/// Her screen has no "この iPhone を外す". A swindler on the phone could talk her into pressing it,
/// and the watching would stop without a sound while her Gmail stayed connected. "家族を削除" stays
/// on her screen: it signs every family iPhone out (401, back to role selection), so the family
/// notices. The author chose this in the review of PR #281.
public enum HomeMenuItem: Hashable, Sendable {
  /// Her settings (`SettingsView`, #222). The family's iPhone has no daily prompt or reading aloud.
  case settings
  /// `DELETE /members/me`: only this iPhone leaves.
  case leaveDevice
  /// `DELETE /families/me`: the whole family goes.
  case deleteFamily

  public static func items(for route: AppRoute) -> [HomeMenuItem] {
    switch route {
    case .chooseRole: []
    case .protectedHome: [.settings, .deleteFamily]
    case .familyHome: [.leaveDevice, .deleteFamily]
    }
  }
}
