import MimamoriCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The share sheet's みまもり (task 12 in docs/plan.md): she shares a screenshot or a photo of a
/// document, it goes to POST /consult, and the answer shows here, with a circle where to press when
/// there is one. Not read aloud: the answer is read aloud only when she asked by voice (#115).
///
/// The image is shrunk to the size Claude reads it at (`ConsultPicture`, shared with the chat's photo
/// button), sent, and dropped with this view; nothing of it is written to disk. Its words are data for Claude, never for this code.
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
    guard let provider, let base = Self.apiBaseURL, let data = await Self.loadData(provider),
      let picture = ConsultPicture(data: data)
    else {
      phase = .failed
      return
    }
    shown = picture.image
    originalSize = picture.original
    guard let image = picture.encoded() else {
      phase = .failed
      return
    }
    let client = APIClient(baseURL: base, store: KeychainDeviceKeyStore())
    do {
      let answer = try await client.consult(image: image)
      phase = .answered(reply: ShareConsult.reply(for: answer), circle: picture.circle(for: answer))
    } catch {
      phase = .failed
    }
  }

  /// The shared image's bytes. `ConsultPicture` shrinks and encodes them, the same as the chat's
  /// photo button does.
  private static func loadData(_ provider: NSItemProvider) async -> Data? {
    await withCheckedContinuation { continuation in
      _ = provider.loadDataRepresentation(for: .image) { data, _ in
        continuation.resume(returning: data)
      }
    }
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
