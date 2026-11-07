#if DEBUG
  import UIKit

  /// Debug builds only: a screenshot-sized picture drawn in the app, standing in for one she picks
  /// with the photo button (`-mimamori-stub-photo-pick`, #221). It looks like a list in Settings, so
  /// the ring the stub puts in its middle lands on a row. Drawn each time; nothing is bundled or kept.
  enum StubPicture {
    static func settingsScreen() -> Data {
      let size = CGSize(width: 1179, height: 2556)
      let format = UIGraphicsImageRendererFormat()
      format.scale = 1
      format.opaque = true
      let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
        UIColor.systemGroupedBackground.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
          .setFill()
        context.fill(CGRect(origin: .zero, size: size))
        let title: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 100)]
        ("一般" as NSString).draw(at: CGPoint(x: 60, y: 260), withAttributes: title)
        let label: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 52)]
        let rows = ["情報", "ソフトウェアアップデート", "AirDrop", "iPhoneストレージ", "日付と時刻", "キーボード", "言語と地域"]
        for (index, row) in rows.enumerated() {
          let rect = CGRect(x: 48, y: 628 + CGFloat(index) * 190, width: size.width - 96, height: 160)
          UIColor.white.setFill()
          UIBezierPath(roundedRect: rect, cornerRadius: 36).fill()
          (row as NSString).draw(at: CGPoint(x: rect.minX + 48, y: rect.minY + 48), withAttributes: label)
        }
      }
      return image.pngData() ?? Data()
    }
  }
#endif
