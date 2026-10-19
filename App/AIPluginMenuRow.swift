import SwiftUI

/// Keep the name, availability and cost distinct without exposing tool schemas.
struct AIPluginMenuRow: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  var plugin: AIPlugin
  var isSelected: Bool
  var select: () -> Void

  private var explanation: String {
    plugin.state.reason ?? AIPluginMenuCopy.summary(id: plugin.id, fallback: plugin.summary)
  }

  var body: some View {
    Button(action: select) {
      HStack(alignment: .top, spacing: MemoraSpacing.md) {
        AIPluginIconView(icon: plugin.icon)
          .frame(width: MemoraSpacing.xxl, height: MemoraSpacing.xxl)
        VStack(alignment: .leading, spacing: MemoraSpacing.xs) {
          HStack(alignment: .firstTextBaseline, spacing: MemoraSpacing.sm) {
            Text(plugin.name)
              .font(MemoraTypography.body.weight(.medium))
              .frame(maxWidth: .infinity, alignment: .leading)
            if !typeSize.isAccessibilitySize { stateLabel }
          }
          if typeSize.isAccessibilitySize { stateLabel }
          Text(explanation)
            .font(MemoraTypography.metadata)
            .foregroundStyle(MemoraPalette.textSecondary)
            .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
          if plugin.state.isReady {
            Text(plugin.cost.rawValue)
              .font(MemoraTypography.metadata)
              .foregroundStyle(MemoraPalette.textSecondary)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .foregroundStyle(MemoraPalette.textPrimary)
      .padding(.horizontal, MemoraSpacing.lg)
      .padding(.vertical, MemoraSpacing.md)
      .frame(maxWidth: .infinity, minHeight: MemoraSpacing.touchTarget, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(CandidateRowStyle(isSelected: isSelected))
    .accessibilityLabel("\(plugin.name)、\(plugin.state.label)")
    .accessibilityValue(plugin.cost.rawValue)
    .accessibilityHint(explanation)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var stateLabel: some View {
    Text(isSelected ? "選択済み" : plugin.state.isReady ? "追加" : plugin.state.label)
      .font(MemoraTypography.metadata.weight(isSelected ? .semibold : .regular))
      .foregroundStyle(isSelected ? MemoraPalette.textPrimary : MemoraPalette.textSecondary)
      .fixedSize(horizontal: true, vertical: false)
  }
}

private struct CandidateRowStyle: ButtonStyle {
  var isSelected: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .background(configuration.isPressed || isSelected ? MemoraPalette.selection : .clear)
  }
}
