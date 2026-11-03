import UIKit

/// Stub until task 12 (sending a screenshot or a message's text to the consult endpoint).
/// It closes right away so a share never hangs.
final class ShareViewController: UIViewController {
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    extensionContext?.completeRequest(returningItems: nil)
  }
}
