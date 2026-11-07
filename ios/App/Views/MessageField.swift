import SwiftUI
import UIKit

/// The text field of her chat, kept in UIKit so what is shown and the value cannot part (#88).
///
/// On the author's iPhone a sent message stayed in SwiftUI's `TextField` while the send button,
/// which follows the value, went away. It was not reproduced on the simulator (iOS 26.5 and 27.1).
/// Here every change in the view, the underlined words still being converted too, is written to
/// `text`, and a new value from outside first confirms those words and then replaces them. Size and
/// padding are left to the caller: `textStyle` sets the letters, the caller pads and draws the
/// background.
struct MessageField: UIViewRepresentable {
  @Binding var text: String
  /// True while the keyboard is up for this field. Setting it false closes the keyboard.
  @Binding var isFocused: Bool
  var placeholder: String
  var textStyle: UIFont.TextStyle
  var maxLines: Int
  /// Read by VoiceOver after the name (the placeholder).
  var hint: String
  /// An image pasted with the field's Paste (#243), as image data. Without it, only words paste.
  var onPasteImage: ((Data) -> Void)? = nil

  func makeUIView(context: Context) -> MessageTextView {
    let view = MessageTextView()
    view.delegate = context.coordinator
    view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return view
  }

  func updateUIView(_ view: MessageTextView, context: Context) {
    context.coordinator.parent = self
    view.onPasteImage = onPasteImage
    view.style(textStyle: textStyle, maxLines: maxLines, placeholder: placeholder, hint: hint)
    context.coordinator.applying {
      view.show(text)
    }
    if isFocused, !view.isFirstResponder {
      // Not yet in a window on the first update; the next run loop turn it is.
      DispatchQueue.main.async { _ = view.becomeFirstResponder() }
    } else if !isFocused, view.isFirstResponder {
      // Resigning can make the keyboard accept a correction and end editing, which writes `text`
      // and `isFocused`; that must not happen in the middle of this update.
      DispatchQueue.main.async { _ = view.resignFirstResponder() }
    }
  }

  func sizeThatFits(_ proposal: ProposedViewSize, uiView view: MessageTextView, context: Context)
    -> CGSize?
  {
    guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
    return CGSize(width: width, height: view.fittingHeight(forWidth: width))
  }

  func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

  @MainActor
  final class Coordinator: NSObject, UITextViewDelegate {
    var parent: MessageField
    /// True while the value is being put into the view, so that change is not written back.
    private var isApplying = false

    init(parent: MessageField) { self.parent = parent }

    func applying(_ change: () -> Void) {
      isApplying = true
      defer { isApplying = false }
      change()
    }

    func textViewDidChange(_ view: UITextView) {
      (view as? MessageTextView)?.refreshPlaceholder()
      guard !isApplying, parent.text != view.text else { return }
      parent.text = view.text
    }

    func textViewDidBeginEditing(_ view: UITextView) {
      if !parent.isFocused { parent.isFocused = true }
    }

    func textViewDidEndEditing(_ view: UITextView) {
      if parent.isFocused { parent.isFocused = false }
    }
  }
}

/// The UIKit view behind `MessageField`.
final class MessageTextView: UITextView {
  let placeholderLabel = UILabel()
  private var maxLines = 5
  /// Takes a pasted image (#243). SwiftUI's and UIKit's text views paste only words.
  var onPasteImage: ((Data) -> Void)?
  /// The general pasteboard; tests put a named one here.
  var pasteboard: UIPasteboard = .general

  init() {
    super.init(frame: .zero, textContainer: nil)
    backgroundColor = .clear
    textColor = .label
    adjustsFontForContentSizeCategory = true
    // The caller pads the field.
    textContainerInset = .zero
    textContainer.lineFragmentPadding = 0
    isScrollEnabled = false
    // Left to UIKit, this was false on a simulator where accessibility had never been on
    // (com.apple.Accessibility AccessibilityEnabled 0) and true once it had been (#86).
    isAccessibilityElement = true

    placeholderLabel.textColor = .placeholderText
    placeholderLabel.adjustsFontForContentSizeCategory = true
    placeholderLabel.isAccessibilityElement = false
    placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
    addSubview(placeholderLabel)
    NSLayoutConstraint.activate([
      placeholderLabel.leadingAnchor.constraint(equalTo: frameLayoutGuide.leadingAnchor),
      placeholderLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: frameLayoutGuide.trailingAnchor),
      placeholderLabel.topAnchor.constraint(equalTo: frameLayoutGuide.topAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  func style(textStyle: UIFont.TextStyle, maxLines: Int, placeholder: String, hint: String) {
    let font = UIFont.preferredFont(forTextStyle: textStyle)
    if self.font?.fontDescriptor.object(forKey: .textStyle) as? UIFont.TextStyle != textStyle {
      self.font = font
      placeholderLabel.font = font
    }
    self.maxLines = max(1, maxLines)
    placeholderLabel.text = placeholder
    accessibilityLabel = placeholder
    accessibilityHint = hint
  }

  /// Puts `value` in the view. Words still being converted are confirmed first, so the keyboard lets
  /// go of them and does not leave them on screen after the value has gone.
  func show(_ value: String) {
    guard text != value else { return }
    if markedTextRange != nil { unmarkText() }
    text = value
    refreshPlaceholder()
  }

  // Paste with an image on the clipboard (#243). `hasImages` only asks what is there and does not
  // tell her the app read the clipboard (Apple's UIPasteboard documentation lists it among the
  // properties that avoid the notice); the image is read only when she presses Paste. When the
  // clipboard holds words too, the words are pasted as before.
  override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
    if action == #selector(paste(_:)), takesImage { return true }
    return super.canPerformAction(action, withSender: sender)
  }

  override func paste(_ sender: Any?) {
    if takesImage, let onPasteImage, let data = pasteboard.image?.pngData() {
      onPasteImage(data)
      return
    }
    guard pasteboard !== UIPasteboard.general else { return super.paste(sender) }
    // A named pasteboard (tests): UITextView's own paste reads only the general one.
    if let words = pasteboard.string { insertText(words) }
  }

  /// An image and no words on the clipboard, and somewhere to put it.
  private var takesImage: Bool {
    onPasteImage != nil && isEditable && pasteboard.hasImages && !pasteboard.hasStrings
  }

  func refreshPlaceholder() {
    placeholderLabel.isHidden = !text.isEmpty
  }

  /// The height for `width`: one line at least, `maxLines` at most, scrolling beyond that.
  func fittingHeight(forWidth width: CGFloat) -> CGFloat {
    let lineHeight = (font ?? .preferredFont(forTextStyle: .body)).lineHeight
    let content = sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
    let limit = ceil(lineHeight * CGFloat(maxLines))
    let scrolls = content > limit + 1
    if isScrollEnabled != scrolls { isScrollEnabled = scrolls }
    return max(ceil(lineHeight), min(content, limit))
  }
}
