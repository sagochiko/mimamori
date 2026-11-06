import MimamoriCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The share sheet's みまもり (task 12 in docs/plan.md): she shares a screenshot or a photo of a
/// document, it goes to POST /consult, and the answer shows here, with a circle where to press when
/// there is one. Not read aloud: the answer is read aloud only when she asked by voice (#115).
///
/// The image is shrunk to the size Claude reads it at (CoordinateMapper), sent, and dropped with this
/// view; nothing of it is written to disk. Its words are data for Claude, never for this code.
final class ShareViewController: UIViewController {
  private let model = ShareModel()

  override func viewDidLoad() {
    super.viewDidLoad()
    model.close = { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) }
    let host = UIHostingController(rootView: ShareView(model: model))
    addChild(host)
    host.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(host.view)
    NSLayoutConstraint.activate([
      host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      host.view.topAnchor.constraint(equalTo: view.topAnchor),
      host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    host.didMove(toParent: self)
    let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
      .flatMap { $0.attachments ?? [] }
    Task {
      await model.send(
        providers.first { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) })
    }
  }
}

@MainActor
@Observable
final class ShareModel {
  enum Phase {
    case sending
    case answered(reply: String, circle: PixelPoint?)
    case failed
  }

  var phase: Phase = .sending
  var shown: UIImage?
  var originalSize = PixelSize(width: 1, height: 1)
  var close: () -> Void = {}

  private static let apiBaseURL: URL? = {
    guard let text = Bundle.main.object(forInfoDictionaryKey: "MimamoriAPIBaseURL") as? String
    else { return nil }
    return URL(string: text)
  }()

  func send(_ provider: NSItemProvider?) async {
    guard let provider, let base = Self.apiBaseURL, let picked = await Self.loadImage(provider)
    else {
      phase = .failed
      return
    }
    shown = picked
    let original = PixelSize(
      width: Int(picked.size.width.rounded()), height: Int(picked.size.height.rounded()))
    originalSize = original
    let sent = CoordinateMapper.sentSize(of: original)
    guard let image = Self.encode(picked, at: sent) else {
      phase = .failed
      return
    }
    let client = APIClient(baseURL: base, store: KeychainDeviceKeyStore())
    do {
      let answer = try await client.consult(image: image)
      phase = .answered(
        reply: ShareConsult.reply(for: answer),
        circle: ShareConsult.circle(for: answer, sent: sent, original: original))
    } catch {
      phase = .failed
    }
  }

  /// The shared image with its orientation applied, at one pixel per point.
  private static func loadImage(_ provider: NSItemProvider) async -> UIImage? {
    await withCheckedContinuation { continuation in
      _ = provider.loadDataRepresentation(for: .image) { data, _ in
        guard let data, let image = UIImage(data: data) else {
          continuation.resume(returning: nil)
          return
        }
        continuation.resume(returning: image)
      }
    }
  }

  /// The image drawn at exactly `size` pixels, as JPEG. A lower quality is tried when the first one
  /// is over what the server takes (server/src/consult.ts, IMAGE_MAX_BASE64_CHARS).
  private static func encode(_ image: UIImage, at size: PixelSize) -> ConsultImage? {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let target = CGSize(width: size.width, height: size.height)
    let drawn = UIGraphicsImageRenderer(size: target, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: target))
    }
    for quality in [0.85, 0.6, 0.4] {
      guard let data = drawn.jpegData(compressionQuality: quality) else { continue }
      if (data.count + 2) / 3 * 4 <= 3_000_000 {
        return ConsultImage(mediaType: .jpeg, data: data, size: size)
      }
    }
    return nil
  }
}

struct ShareView: View {
  let model: ShareModel

  var body: some View {
    VStack(spacing: 16) {
      if let image = model.shown {
        CircledImage(image: image, original: model.originalSize, circle: circle)
      }
      switch model.phase {
      case .sending:
        ProgressView()
          .accessibilityLabel("みまもりに見せています")
      case .answered(let reply, _):
        Text(reply)
          .font(.body)
          .frame(maxWidth: .infinity, alignment: .leading)
      case .failed:
        Text("送れませんでした")
          .font(.body)
          .accessibilityHint("通信か、みまもりの登録を確かめて、もう一度共有してください")
      }
      Button("閉じる") { model.close() }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemBackground))
  }

  private var circle: PixelPoint? {
    if case .answered(_, let circle) = model.phase { return circle }
    return nil
  }
}

/// The shared image, fitted, with a ring where to press.
struct CircledImage: View {
  let image: UIImage
  let original: PixelSize
  let circle: PixelPoint?

  var body: some View {
    GeometryReader { geo in
      let scale = min(
        geo.size.width / CGFloat(original.width), geo.size.height / CGFloat(original.height))
      let shown = CGSize(
        width: CGFloat(original.width) * scale, height: CGFloat(original.height) * scale)
      let origin = CGPoint(
        x: (geo.size.width - shown.width) / 2, y: (geo.size.height - shown.height) / 2)
      ZStack(alignment: .topLeading) {
        Image(uiImage: image)
          .resizable()
          .frame(width: shown.width, height: shown.height)
          .offset(x: origin.x, y: origin.y)
        if let circle {
          Circle()
            .stroke(Color.red, lineWidth: 5)
            .frame(width: 56, height: 56)
            .position(x: origin.x + circle.x * scale, y: origin.y + circle.y * scale)
        }
      }
    }
    .accessibilityElement()
    .accessibilityLabel(circle == nil ? "見せた画像" : "見せた画像。押す場所に赤い丸")
  }
}
