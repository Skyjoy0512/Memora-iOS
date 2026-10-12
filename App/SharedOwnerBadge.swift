import SwiftUI

/// Marks something as a teammate's, never this person's own: their name on a
/// tinted capsule.
struct SharedOwnerBadge: View {
  var ownerName: String

  var body: some View {
    Label(ownerName, icon: .personCropCircleFill)
      .font(.caption.weight(.semibold))
      .lineLimit(1)
      .foregroundStyle(MemoraPalette.textSecondary)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(MemoraPalette.secondaryBackground, in: Capsule())
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("\(ownerName)さんが共有")
  }
}
