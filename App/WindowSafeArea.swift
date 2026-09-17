import SwiftUI
import UIKit

/// The window's safe area insets.
///
/// The drawer's full-bleed container makes SwiftUI report zero insets to its
/// content, so views that need to stay clear of the status bar or the home
/// indicator read the real values from the window instead.
enum WindowSafeArea {
  static var insets: EdgeInsets {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
    let insets = (windows.first { $0.isKeyWindow } ?? windows.first)?.safeAreaInsets ?? .zero
    return EdgeInsets(top: insets.top, leading: insets.left, bottom: insets.bottom, trailing: insets.right)
  }
}
