import SwiftUI

/// Keep the spoken action even when a toolbar only displays its icon.
struct ToolbarIconButton: View {
  var title: LocalizedStringKey
  var icon: MemoraIcon
  var artwork: MemoraArtwork?
  var action: () -> Void
  @Environment(\.memoraToolbarControlSize) private var controlSize

  init(_ title: LocalizedStringKey, icon: MemoraIcon, artwork: MemoraArtwork? = nil, action: @escaping () -> Void) {
    self.title = title
    self.icon = icon
    self.artwork = artwork
    self.action = action
  }

  var body: some View {
    Button {
      InteractionFeedback.shared.send(.tap)
      action()
    } label: {
      ToolbarIconGlyph(icon: icon, artwork: artwork)
        .frame(width: controlSize, height: controlSize)
        .contentShape(Rectangle())
    }
    .accessibilityLabel(title)
  }
}
