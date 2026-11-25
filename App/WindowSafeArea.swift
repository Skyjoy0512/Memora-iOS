import SwiftUI
import UIKit

/// The window's safe area insets.
///
/// Used to compare a global frame with the window's safe area.
enum WindowSafeArea {
  static var insets: EdgeInsets {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
    let insets = (windows.first { $0.isKeyWindow } ?? windows.first)?.safeAreaInsets ?? .zero
    return EdgeInsets(top: insets.top, leading: insets.left, bottom: insets.bottom, trailing: insets.right)
  }
}
