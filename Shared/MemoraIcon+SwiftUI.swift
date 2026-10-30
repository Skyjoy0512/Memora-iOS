import SwiftUI
import LucideSwift
import UIKit

// Shared labels preserve native menu, toolbar and VoiceOver behavior.
// Stored identifiers resolve through the same Lucide map on every surface.

extension Image {
  init(icon: MemoraIcon, size: CGFloat = 20) {
    if let image = MemoraIconRendering.image(icon, size: size) {
      self = Image(image, scale: MemoraIconRendering.scale, label: Text("")).renderingMode(.template)
    } else {
      self.init(uiImage: UIImage())
    }
  }
}

extension UIImage {
  convenience init?(icon: MemoraIcon, size: CGFloat = 20) {
    guard let image = MemoraIconRendering.image(icon, size: size) else { return nil }
    self.init(cgImage: image, scale: MemoraIconRendering.scale, orientation: .up)
  }
}

extension Label where Title == Text, Icon == Image {
  init(_ titleKey: LocalizedStringKey, icon: MemoraIcon, size: CGFloat = 20) {
    self.init {
      Text(titleKey)
    } icon: {
      Image(icon: icon, size: size)
    }
  }

  @_disfavoredOverload
  init<S: StringProtocol>(_ title: S, icon: MemoraIcon, size: CGFloat = 20) {
    self.init {
      Text(title)
    } icon: {
      Image(icon: icon, size: size)
    }
  }
}

extension Button where Label == SwiftUI.Label<Text, Image> {
  init(
    _ titleKey: LocalizedStringKey,
    icon: MemoraIcon,
    size: CGFloat = 20,
    role: ButtonRole? = nil,
    action: @escaping () -> Void
  ) {
    self.init(role: role, action: action) {
      SwiftUI.Label(titleKey, icon: icon, size: size)
    }
  }

  @_disfavoredOverload
  init<S: StringProtocol>(
    _ title: S,
    icon: MemoraIcon,
    size: CGFloat = 20,
    role: ButtonRole? = nil,
    action: @escaping () -> Void
  ) {
    self.init(role: role, action: action) {
      SwiftUI.Label(title, icon: icon, size: size)
    }
  }
}

extension Menu where Label == SwiftUI.Label<Text, Image> {
  init(
    _ titleKey: LocalizedStringKey,
    icon: MemoraIcon,
    @ViewBuilder content: () -> Content
  ) {
    self.init(content: content) {
      SwiftUI.Label(titleKey, icon: icon)
    }
  }
}

extension ContentUnavailableView where Label == SwiftUI.Label<Text, Image>, Description == Text?, Actions == EmptyView {
  init(_ title: LocalizedStringKey, icon: MemoraIcon, description: Text? = nil) {
    self.init {
      SwiftUI.Label {
        Text(title)
      } icon: {
        Image(icon: icon, size: 48)
      }
    } description: {
      description
    }
  }
}
