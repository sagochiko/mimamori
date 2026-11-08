import MimamoriCore
import SwiftUI

/// Smiles in one row, newest first. A tap opens one large. With `onCamera`, the row starts with the
/// button that opens the smile camera. Only photos show: the author dropped the set words ("ひと言")
/// from both screens on 2026-11-07 (#223). The family's screen shows everyone's, large with names;
/// her screen (`compact`) shows only the family's, as thin as the notice strip, names in VoiceOver
/// only (the author chose this on 2026-11-07, #243).
struct SmileStrip: View {
  @Environment(AppModel.self) private var model
  var onCamera: (() -> Void)?
  /// With it, the menu with "この iPhone を外す" and "家族を削除" comes last in the row (her screen, which has no toolbar).
  var showsMenu = false
  /// Her screen: the family's smiles only (`SmileBoard.familyPhotos`), small.
  var compact = false
  @State private var opened: Smile?

  var body: some View {
    let size: CGFloat = compact ? 40 : 72
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: compact ? .center : .top, spacing: compact ? 8 : 12) {
        if let onCamera {
          CameraButton(size: size, action: onCamera)
        }
        ForEach(compact ? model.smileBoard.familyPhotos : model.smileBoard.photos) { smile in
          Button {
            opened = smile
          } label: {
            SmileTile(smile: smile, size: size, showsName: !compact)
          }
          .buttonStyle(.plain)
        }
        if showsMenu {
          WipeMenu().frame(height: max(size, 44))
        }
      }
      .padding(.horizontal, 2)
    }
    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    .sheet(item: $opened) { smile in
      SmileDetail(smile: smile)
        .presentationDetents([.large])
    }
  }
}

private struct CameraButton: View {
  var size: CGFloat = 72
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "face.smiling")
        .font(size < 72 ? .title3 : .title)
        // Her small button keeps its glyph inside the circle; the family's is as before.
        .dynamicTypeSize(...(size < 72 ? DynamicTypeSize.xxxLarge : .accessibility5))
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .background(Circle().fill(Color.accentColor))
        // At least 44 points to press.
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("笑顔を撮る")
    .accessibilityHint("前のカメラに向かって笑うと、その場で撮って家族に送ります。ボタンを押す必要はありません")
  }
}

/// One smile: the photo, with the sender's name under it unless `showsName` is false (her screen,
/// where VoiceOver still reads it).
struct SmileTile: View {
  let smile: Smile
  var size: CGFloat = 72
  var showsName = true

  var body: some View {
    VStack(spacing: 4) {
      SmilePhoto(smile: smile)
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size < 72 ? 10 : 16))
        .frame(minWidth: 44, minHeight: 44)
      if showsName {
        Text(smile.displayName)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(smile.spokenLabel)
    .accessibilityHint("押すと大きく見られます")
  }
}

extension Smile {
  /// "(name)の笑顔、(time)", for VoiceOver.
  var spokenLabel: String {
    let time = createdAt.formatted(.dateTime.month().day().hour().minute())
    return "\(displayName)の笑顔、\(time)"
  }
}

/// The photo, fetched with the device key. A soft placeholder until it arrives.
struct SmilePhoto: View {
  @Environment(AppModel.self) private var model
  let smile: Smile
  @State private var image: UIImage?

  var body: some View {
    ZStack {
      Color(.secondarySystemBackground)
      if let image {
        Image(uiImage: image).resizable().scaledToFill()
      } else {
        Image(systemName: "face.smiling").font(.title2).foregroundStyle(.tertiary)
      }
    }
    .task(id: smile.id) {
      if let data = await model.photo(for: smile) { image = UIImage(data: data) }
    }
    .accessibilityHidden(true)
  }
}

private struct SmileDetail: View {
  let smile: Smile
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 16) {
      SmilePhoto(smile: smile)
        .aspectRatio(3 / 4, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 24))
      Text(smile.displayName).font(.headline)
      Spacer(minLength: 0)
      Button("閉じる") { dismiss() }
        .buttonStyle(BigButtonStyle(prominent: false))
    }
    .padding(24)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(smile.spokenLabel)
  }
}

/// The smile camera, full screen. It takes the photo by itself when she smiles; there is no shutter
/// button, only "やめる". The photo shows for a moment while it is sent, then the screen closes.
struct SmileCaptureView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var taken: UIImage?

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      if let taken {
        Image(uiImage: taken).resizable().scaledToFit()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .accessibilityLabel("撮れました。家族に送っています")
        ProgressView().tint(.white).controlSize(.large)
      } else {
        camera
      }
    }
    .overlay(alignment: .topLeading) {
      if taken == nil {
        Button("やめる") { dismiss() }
          .font(.headline)
          .foregroundStyle(.white)
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
          .background(Capsule().fill(.black.opacity(0.4)))
          .padding(16)
          .accessibilityHint("撮らずに閉じます")
      }
    }
  }

  @ViewBuilder private var camera: some View {
    #if DEBUG
      if ScreenshotStubTransport.isRequested && !SmileCamera.isSupported {
        StubSmileCamera { captured($0, $1) }
      } else {
        liveCamera
      }
    #else
      liveCamera
    #endif
  }

  @ViewBuilder private var liveCamera: some View {
    if SmileCamera.isSupported {
      // Takes the size it is given, like the stand-in, so nothing is pushed off the screen.
      SmileCameraPreview { captured($0, $1) }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .ignoresSafeArea()
        .accessibilityLabel("前のカメラ")
        .accessibilityHint("カメラに向かって笑うと、その場で撮って家族に送ります")
    } else {
      // Face tracking needs the TrueDepth camera (Face ID iPhones).
      Image(systemName: "camera")
        .font(.largeTitle)
        .foregroundStyle(.white.opacity(0.6))
        .accessibilityLabel("この iPhone では笑顔のカメラを使えません")
    }
  }

  private func captured(_ jpeg: Data, _ score: Double) {
    guard taken == nil else { return }
    taken = UIImage(data: jpeg)
    Task {
      _ = await model.sendSmile(jpeg: jpeg, score: score)
      // On failure the alert shows once this screen is gone.
      dismiss()
    }
  }
}
