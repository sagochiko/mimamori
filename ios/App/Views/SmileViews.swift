import MimamoriCore
import SwiftUI

/// Everyone's smiles and replies in one row, newest first, on both home screens. A tap opens one
/// large. With `onCamera`, the row starts with the button that opens the smile camera.
struct SmileStrip: View {
  @Environment(AppModel.self) private var model
  var onCamera: (() -> Void)?
  @State private var opened: Smile?

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: .top, spacing: 12) {
        if let onCamera {
          CameraButton(action: onCamera)
        }
        ForEach(model.smileBoard.smiles) { smile in
          Button {
            opened = smile
          } label: {
            SmileTile(smile: smile)
          }
          .buttonStyle(.plain)
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
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "face.smiling")
        .font(.title)
        .foregroundStyle(.white)
        .frame(width: 72, height: 72)
        .background(Circle().fill(Color.accentColor))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("笑顔を撮る")
    .accessibilityHint("前のカメラに向かって笑うと、その場で撮って家族に送ります。ボタンを押す必要はありません")
  }
}

/// One smile: the photo, a reply, or both, with the sender's name under it.
struct SmileTile: View {
  let smile: Smile

  var body: some View {
    VStack(spacing: 4) {
      if smile.hasPhoto {
        SmilePhoto(smile: smile)
          .frame(width: 72, height: 72)
          .clipShape(RoundedRectangle(cornerRadius: 16))
      }
      if let note = smile.note {
        Text(note)
          .font(.footnote)
          .lineLimit(smile.hasPhoto ? 1 : 3)
          .multilineTextAlignment(.leading)
          .padding(.horizontal, 10)
          .padding(.vertical, 8)
          .frame(width: smile.hasPhoto ? 72 : 120, alignment: .leading)
          .frame(minHeight: smile.hasPhoto ? nil : 72)
          .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
      }
      Text(smile.displayName)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(smile.spokenLabel)
    .accessibilityHint("押すと大きく見られます")
  }
}

extension Smile {
  /// "(name)の笑顔、(time)" and the reply, for VoiceOver.
  var spokenLabel: String {
    let time = createdAt.formatted(.dateTime.month().day().hour().minute())
    let what = hasPhoto ? "\(displayName)の笑顔" : "\(displayName)からひと言"
    return [what, note, time].compactMap(\.self).joined(separator: "、")
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
      if smile.hasPhoto {
        SmilePhoto(smile: smile)
          .aspectRatio(3 / 4, contentMode: .fit)
          .clipShape(RoundedRectangle(cornerRadius: 24))
      }
      if let note = smile.note {
        Text(note).font(.title3).frame(maxWidth: .infinity, alignment: .leading)
      }
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
      SmileCameraPreview { captured($0, $1) }
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

/// "ひと言": one line to the family, without a photo.
struct NoteSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var text = ""
  @State private var sending = false
  @FocusState private var focused: Bool

  private static let limit = 60

  var body: some View {
    VStack(spacing: 16) {
      TextField("ひと言", text: $text, axis: .vertical)
        .font(.title3)
        .lineLimit(1...3)
        .focused($focused)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
        .onChange(of: text) { _, new in
          if new.count > Self.limit { text = String(new.prefix(Self.limit)) }
        }
        .accessibilityHint("家族みんなに届く、\(Self.limit)字までのひと言を書きます")
      Button {
        sending = true
        Task {
          if await model.sendNote(text) { dismiss() }
          sending = false
        }
      } label: {
        if sending { ProgressView().tint(.white) } else { Text("送る") }
      }
      .buttonStyle(BigButtonStyle())
      .disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      .accessibilityLabel("ひと言を送る")
      Spacer(minLength: 0)
    }
    .padding(24)
    .onAppear { focused = true }
  }
}
