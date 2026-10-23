import SwiftUI

struct WorkspaceSelectionRow: View {
  var workspace: Workspace
  var isSelected: Bool
  var onSelect: () -> Void

  var body: some View {
    Button(action: onSelect) {
      HStack(spacing: MemoraSpacing.md) {
        MemoraInterfaceIcon(icon: workspace.icon)
        VStack(alignment: .leading, spacing: MemoraSpacing.xs) {
          Text(workspace.title).font(.body.weight(.medium))
          Text(workspace.storageDescription)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        Image(icon: .checkmark, size: MemoraIconMetrics.glyph)
          .opacity(isSelected ? 1 : 0)
          .accessibilityHidden(true)
      }
      .frame(maxWidth: .infinity, minHeight: MemoraSpacing.touchTarget, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(workspace.title)
    .accessibilityValue(isSelected ? "選択中、\(workspace.storageDescription)" : workspace.storageDescription)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityIdentifier("workspace.option.\(workspace.id)")
  }
}
