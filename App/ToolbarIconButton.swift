import SwiftUI

/// Keep the spoken action even when a toolbar only displays its icon.
struct ToolbarIconButton: View {
  var title: LocalizedStringKey
  var icon: MemoraIcon
  var artwork: MemoraArtwork?
  var action: () -> Void
  @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 20

  init(_ title: LocalizedStringKey, icon: MemoraIcon, artwork: MemoraArtwork? = nil, action: @escaping () -> Void) {
    self.title = title
    self.icon = icon
    self.artwork = artwork
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      Group {
        if let artwork {
          ArtworkIcon(artwork: artwork, size: iconSize)
        } else {
          Image(icon: icon, size: iconSize)
        }
      }
        .font(.system(size: iconSize))
        .frame(minWidth: 36, minHeight: 36)
        .contentShape(Rectangle())
    }
    .accessibilityLabel(title)
  }
}
