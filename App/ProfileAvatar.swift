import SwiftUI

/// The person's own round picture: a photo, a Memoji on its background, or a
/// neutral silhouette until one is chosen.
struct ProfileAvatar: View {
  var profile: UserProfile
  var size: CGFloat

  var body: some View {
    ZStack {
      switch profile.avatarKind {
      case .photo:
        if let avatar = profile.avatar {
          Image(uiImage: avatar)
            .renderingMode(.original)
            .resizable()
            .scaledToFill()
        }
      case .sticker:
        profile.background.gradient
        if let avatar = profile.avatar {
          Image(uiImage: avatar)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .padding(size * 0.08)
            .offset(y: size * 0.04)
        }
      case .none:
        Color.primary.opacity(0.08)
        Image(icon: .personFill)
          .resizable()
          .scaledToFit()
          .foregroundStyle(.secondary)
          .padding(size * 0.24)
      }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
    .accessibilityHidden(true)
  }
}
