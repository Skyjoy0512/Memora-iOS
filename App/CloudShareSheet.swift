import CloudKit
import SwiftUI
import UIKit

/// Presents the system sharing sheet for a CloudKit share, so people are invited
/// with the controls iOS already provides (Messages, Mail, a link).
struct CloudShareSheet: UIViewControllerRepresentable {
  var share: CKShare
  var container: CKContainer
  var onFinish: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(onFinish: onFinish)
  }

  func makeUIViewController(context: Context) -> UICloudSharingController {
    let controller = UICloudSharingController(share: share, container: container)
    controller.delegate = context.coordinator
    controller.availablePermissions = [.allowReadOnly, .allowReadWrite]
    return controller
  }

  func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

  final class Coordinator: NSObject, UICloudSharingControllerDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
      self.onFinish = onFinish
    }

    func itemTitle(for csc: UICloudSharingController) -> String? {
      nil
    }

    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
      onFinish()
    }

    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
      onFinish()
    }

    func cloudSharingController(
      _ csc: UICloudSharingController,
      failedToSaveShareWithError error: any Error
    ) {
      onFinish()
    }
  }
}
