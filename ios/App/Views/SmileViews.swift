import MimamoriCore
import SwiftUI

/// Everyone's smiles and replies in one row, newest first, on both home screens. A tap opens one
/// large. With `onCamera` (and `onNote`), the row starts with the buttons that open the smile camera
/// (and the set words).
struct SmileStrip: View {
  @Environment(AppModel.self) private var model
  var onCamera: (() -> Void)?
  /// With it, a second button opens the set words.
  var onNote: (() -> Void)?
  @State private var opened: Smile?

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: .top, spacing: 12) {
        if let onCamera {
          CameraButton(action: onCamera)
        }
        if let onNote {
          NoteButton(action: onNote)
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

private struct NoteButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "text.bubble")
        .font(.title)
        .foregroundStyle(Color.accentColor)
        .frame(width: 72, height: 72)
        .background(Circle().fill(Color.accentColor.opacity(0.15)))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("ひと言を送る")
    .accessibilityHint("「おはよう」などの決まった言葉から選んで、家族みんなに送ります")
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

/// "ひと言": one of the set words to the family, without a photo. No free text: the author chose set
/// words on 2026-11-05 (docs/design.md, "毎朝の笑顔"). A tap sends at once.
struct NoteSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var sending: SmileNote?

  var body: some View {
    ScrollView {
      VStack(spacing: 12) {
        ForEach(SmileNote.allCases) { note in
          Button {
            guard sending == nil else { return }
            sending = note
            Task {
              if await model.sendNote(note) { dismiss() }
              sending = nil
            }
          } label: {
            if sending == note { ProgressView() } else { Text(note.text) }
          }
          .buttonStyle(BigButtonStyle(prominent: false))
          .disabled(sending != nil)
          .accessibilityLabel(note.text)
          .accessibilityHint("押すと、このひと言を家族みんなに送ります")
        }
      }
      .padding(24)
    }
  }
}
