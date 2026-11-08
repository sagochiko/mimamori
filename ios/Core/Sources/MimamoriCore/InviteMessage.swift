import Foundation

/// What 「送る」 under the invite code sends (#279). It used to be the six digits alone, and the author
/// asked whether the family would know what to do with them ("何の説明もないので不親切"). The message
/// reaches another person, so it carries the steps; the screen itself stays without explanation.
/// The button names in the steps are the ones on screen: 「家族」 and 「見守られる人」 on role selection,
/// 「入る」 on the name screen and the code screen.
public enum InviteMessage {
  /// The public TestFlight link of the external group 「審査員と家族」, the same one as in README.
  public static let appLink = URL(string: "https://testflight.apple.com/join/EZhN4k78")!

  /// "11月9日 10:38": the screen shows it with "まで", the message with "まで使えます".
  public static func expiry(_ date: Date, timeZone: TimeZone = .current) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let c = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
    return "\(c.month ?? 0)月\(c.day ?? 0)日 \(c.hour ?? 0):" + String(format: "%02d", c.minute ?? 0)
  }

  /// The whole message, code and expiry filled in.
  public static func text(for invite: Invite, timeZone: TimeZone = .current) -> String {
    """
    みまもりで家族に入ってください。
    1. このリンクからアプリを入れる \(appLink.absoluteString)
    2. アプリを開いて「家族」を選び、自分の名前を入れて「入る」を押す(見守られる本人は「見守られる人」を選ぶ)
    3. コード \(invite.code.value) を入れて「入る」を押す
    コードは\(expiry(invite.expiresAt, timeZone: timeZone))まで使えます。
    """
  }
}
