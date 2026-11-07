import SwiftUI
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import Mimamori

/// The text field of her chat (#88). On the author's iPhone a sent message stayed in the field while
/// the send button, which follows the value, went away. These tests drive the field the way the
/// keyboard does (marked text is the underlined Japanese still being converted) and check that what
/// is shown and the value never part.
@MainActor
struct MessageFieldTests {
  @Observable @MainActor final class Box {
    var text = ""
    var focused = false
  }

  private struct Host: View {
    @Bindable var box: Box
    var body: some View {
      MessageField(
        text: $box.text, isFocused: $box.focused, placeholder: "メッセージ", textStyle: .title3,
        maxLines: 5, hint: "書いて送る")
    }
  }

  private let box = Box()
  private let window: UIWindow

  init() throws {
    let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
    window = UIWindow(windowScene: scene)
    window.rootViewController = UIHostingController(rootView: Host(box: box))
    window.makeKeyAndVisible()
  }

  private func field() async throws -> MessageTextView {
    try await settle()
    return try #require(Self.find(in: window))
  }

  private static func find(in view: UIView) -> MessageTextView? {
    if let field = view as? MessageTextView { return field }
    return view.subviews.lazy.compactMap { find(in: $0) }.first
  }

  /// Lets SwiftUI run its update after a change, as the next frame would.
  private func settle() async throws { try await Task.sleep(for: .milliseconds(200)) }

  @Test func sendingWhileConvertingEmptiesTheFieldAndTheNextWordsShowTheButtonAgain() async throws {
    let field = try await field()
    _ = field.becomeFirstResponder()
    field.setMarkedText("それってか", selectedRange: NSRange(location: 5, length: 0))
    #expect(field.markedTextRange != nil)
    #expect(box.text == "それってか")

    box.text = ""  // what the send button does
    try await settle()
    #expect(field.text == "")
    #expect(field.markedTextRange == nil)

    field.insertText("は")
    #expect(box.text == "は")
    #expect(field.text == "は")
  }

  /// A small image, as a copied screenshot would be.
  private static func picture() -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: 30, height: 60), format: format).image { context in
      UIColor.systemTeal.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 30, height: 60))
    }
  }

  // #243: the field's long press paste took only text. A named pasteboard stands in for the general
  // one, so the test reads nothing of the Mac's or the simulator's clipboard.
  @Test func pastingAnImageHandsItToTheChatAndWritesNothing() async throws {
    let field = try await field()
    _ = field.becomeFirstResponder()
    let board = UIPasteboard.withUniqueName()
    defer { UIPasteboard.remove(withName: board.name) }
    field.pasteboard = board
    var pasted: [Data] = []
    field.onPasteImage = { pasted.append($0) }
    board.image = Self.picture()

    #expect(field.canPerformAction(#selector(UIResponderStandardEditActions.paste(_:)), withSender: nil))
    field.paste(nil)
    #expect(pasted.count == 1)
    let data = try #require(pasted.first)
    let image = try #require(UIImage(data: data))
    #expect(image.size == CGSize(width: 30, height: 60))
    #expect(field.text == "")
    #expect(box.text == "")
  }

  @Test func pastingWordsStillPastesWords() async throws {
    let field = try await field()
    _ = field.becomeFirstResponder()
    let board = UIPasteboard.withUniqueName()
    defer { UIPasteboard.remove(withName: board.name) }
    field.pasteboard = board
    var pasted = 0
    field.onPasteImage = { _ in pasted += 1 }
    // Words and an image both: the words are pasted, as before #243.
    board.items = [
      [UTType.utf8PlainText.identifier: "Wi-Fi がつながらない", UTType.png.identifier: try #require(Self.picture().pngData())]
    ]
    #expect(board.hasImages)

    field.paste(nil)
    #expect(pasted == 0)
    #expect(box.text == "Wi-Fi がつながらない")
  }

  @Test func withoutAPlaceForImagesAnImageCannotBePasted() async throws {
    let field = try await field()
    _ = field.becomeFirstResponder()
    let board = UIPasteboard.withUniqueName()
    defer { UIPasteboard.remove(withName: board.name) }
    field.pasteboard = board
    field.onPasteImage = nil
    board.image = Self.picture()
    #expect(!field.canPerformAction(#selector(UIResponderStandardEditActions.paste(_:)), withSender: nil))
  }

  @Test func sendingConfirmedWordsEmptiesTheField() async throws {
    let field = try await field()
    _ = field.becomeFirstResponder()
    field.insertText("それってどういうこと?")
    #expect(box.text == "それってどういうこと?")

    box.text = ""
    try await settle()
    #expect(field.text == "")
  }

  @Test func aValueSetFromOutsideIsShown() async throws {
    let field = try await field()
    box.text = "電話の相談"  // the screenshot stub's draft
    try await settle()
    #expect(field.text == "電話の相談")
  }

  @Test func theReturnKeyStartsANewLine() async throws {
    let field = try await field()
    _ = field.becomeFirstResponder()
    field.insertText("一行目")
    field.insertText("\n")
    field.insertText("二行目")
    #expect(box.text == "一行目\n二行目")
  }

  @Test func growsWithItsLinesUpToTheLimitThenScrolls() async throws {
    let field = try await field()
    let width: CGFloat = 280
    let one = field.fittingHeight(forWidth: width)
    field.text = "1\n2\n3"
    let three = field.fittingHeight(forWidth: width)
    field.text = (1...12).map(String.init).joined(separator: "\n")
    let twelve = field.fittingHeight(forWidth: width)
    #expect(three > one)
    #expect(twelve < one * 6)
    #expect(field.isScrollEnabled)
    field.text = "1"
    _ = field.fittingHeight(forWidth: width)
    #expect(!field.isScrollEnabled)
  }

  @Test func focusFollowsTheBindingBothWays() async throws {
    let field = try await field()
    box.focused = true
    try await settle()
    #expect(field.isFirstResponder)

    box.focused = false  // the microphone closes the keyboard
    try await settle()
    #expect(!field.isFirstResponder)

    _ = field.becomeFirstResponder()  // she taps the field
    try await settle()
    #expect(box.focused)
  }

  @Test func voiceOverReadsTheNameAndTheHint() async throws {
    let field = try await field()
    #expect(field.isAccessibilityElement)
    #expect(field.accessibilityLabel == "メッセージ")
    #expect(field.accessibilityHint == "書いて送る")
  }

  @Test func thePlaceholderShowsOnlyWhileEmpty() async throws {
    let field = try await field()
    #expect(!field.placeholderLabel.isHidden)
    _ = field.becomeFirstResponder()
    field.setMarkedText("そ", selectedRange: NSRange(location: 1, length: 0))
    #expect(field.placeholderLabel.isHidden)
    box.text = ""
    try await settle()
    #expect(!field.placeholderLabel.isHidden)
  }
}

/// The host app is launched by these tests; without the stub it would reach the real backend.
@Test func theHostAppRunsOnTheStub() {
  #expect(ProcessInfo.processInfo.arguments.contains("-mimamori-stub"))
}
