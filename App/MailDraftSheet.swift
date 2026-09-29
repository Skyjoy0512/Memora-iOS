import MessageUI
import SwiftUI

/// Opens the agent's email in Mail's composer, so the person reviews and sends
/// it. Without a Mail account it falls back to the share sheet with the text.
struct MailDraftSheet: View {
  var draft: MailDraft
  var onFinish: () -> Void

  var body: some View {
    if MFMailComposeViewController.canSendMail() {
      MailComposer(draft: draft, onFinish: onFinish)
        .ignoresSafeArea()
    } else {
      ActivityView(items: [draft.plainText], onComplete: onFinish)
    }
  }
}

private struct MailComposer: UIViewControllerRepresentable {
  var draft: MailDraft
  var onFinish: () -> Void

  func makeUIViewController(context: Context) -> MFMailComposeViewController {
    let controller = MFMailComposeViewController()
    controller.setToRecipients(draft.recipients)
    controller.setSubject(draft.subject)
    controller.setMessageBody(draft.body, isHTML: false)
    controller.mailComposeDelegate = context.coordinator
    return controller
  }

  func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(onFinish: onFinish)
  }

  final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
    var onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
      self.onFinish = onFinish
    }

    func mailComposeController(
      _ controller: MFMailComposeViewController,
      didFinishWith result: MFMailComposeResult,
      error: (any Error)?
    ) {
      onFinish()
    }
  }
}
