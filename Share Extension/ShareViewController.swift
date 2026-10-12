import UIKit
import SwiftUI

final class ShareViewController: UIViewController {
  override func viewDidLoad() {
    super.viewDidLoad()
    let host = UIHostingController(rootView: ShareCaptureView(context: extensionContext))
    addChild(host)
    view.addSubview(host.view)
    host.view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      host.view.topAnchor.constraint(equalTo: view.topAnchor),
      host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])
    host.didMove(toParent: self)
  }
}
