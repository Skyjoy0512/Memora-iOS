import SwiftUI
import UIKit

// Mirrors the `systemImage:` initializers, so an icon reads the same at every
// call site and keeps the behaviors that come with a Label (icon-only toolbar
// items, menu rows, VoiceOver names).

extension Image {
  init(icon: MemoraIcon) {
    // Resolve custom symbol assets before handing them to SwiftUI's control
    // labels, which can otherwise reinterpret a named image in native chrome.
    self.init(uiImage: UIImage(icon: icon) ?? UIImage())
    self = renderingMode(.template)
  }
}

extension UIImage {
  convenience init?(icon: MemoraIcon, configuration: UIImage.SymbolConfiguration? = nil) {
    self.init(named: icon.assetName, in: .main, with: configuration)
  }
}

extension Label where Title == Text, Icon == Image {
  init(_ titleKey: LocalizedStringKey, icon: MemoraIcon) {
    self.init {
      Text(titleKey)
    } icon: {
      Image(icon: icon)
    }
  }

  @_disfavoredOverload
  init<S: StringProtocol>(_ title: S, icon: MemoraIcon) {
    self.init {
      Text(title)
    } icon: {
      Image(icon: icon)
    }
  }
}

extension Button where Label == SwiftUI.Label<Text, Image> {
  init(
    _ titleKey: LocalizedStringKey,
    icon: MemoraIcon,
    role: ButtonRole? = nil,
    action: @escaping () -> Void
  ) {
    self.init(role: role, action: action) {
      SwiftUI.Label(titleKey, icon: icon)
    }
  }

  @_disfavoredOverload
  init<S: StringProtocol>(
    _ title: S,
    icon: MemoraIcon,
    role: ButtonRole? = nil,
    action: @escaping () -> Void
  ) {
    self.init(role: role, action: action) {
      SwiftUI.Label(title, icon: icon)
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
    self.init(title, image: icon.assetName, description: description)
  }
}
