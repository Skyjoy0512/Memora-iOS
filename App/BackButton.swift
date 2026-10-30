import SwiftUI

extension View {
  // Keep the system's back control and interactive navigation rather than replacing it with a dismiss button.
  func memoraBackButton() -> some View {
    navigationBarBackButtonHidden(false)
  }
}
