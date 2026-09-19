import SwiftUI
import UIKit

/// A round avatar for a person: their photo when set, otherwise their initial.
struct PersonAvatar: View {
  var name: String
  var size: CGFloat = 40
  var photoData: Data? = nil

  var body: some View {
    Group {
      if let photoData, let image = UIImage(data: photoData) {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        ZStack {
          Circle()
            .fill(Color.primary.opacity(0.08))
          Text(String(name.prefix(1)))
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.primary)
        }
      }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
    .accessibilityHidden(true)
  }
}
