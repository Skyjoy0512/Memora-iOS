import SwiftUI

struct AIPluginMenu: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  var candidates: [AIPlugin]
  var selectedIDs: Set<String> = []
  var maximumHeight: CGFloat
  var select: (AIPlugin) -> Void
  var cancel: () -> Void
  @ScaledMetric(relativeTo: .body) private var rowHeight = 64

  var body: some View {
    let groups = AIPlugin.Kind.allCases.compactMap { kind -> (AIPlugin.Kind, [AIPlugin])? in
      let rows = candidates.filter { $0.kind == kind }
      return rows.isEmpty ? nil : (kind, rows)
    }
    VStack(spacing: 0) {
      HStack {
        Text("ツール・スキル・ソース")
          .font(MemoraTypography.metadata).foregroundStyle(MemoraPalette.textSecondary)
        Spacer(minLength: 4)
        MemoraIconButton("候補を閉じる", icon: .xmark, action: cancel)
      }
      .padding(.horizontal, MemoraSpacing.md)
      Divider()
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          if candidates.isEmpty {
            Text("候補がありません")
              .font(.subheadline).foregroundStyle(.secondary).padding(MemoraSpacing.lg)
          }
          ForEach(groups, id: \.0) { kind, rows in
            Text(kind.rawValue).font(.caption).foregroundStyle(.secondary)
              .padding(.horizontal, MemoraSpacing.lg).padding(.top, MemoraSpacing.md)
            ForEach(rows) { plugin in
              Button { select(plugin) } label: {
                HStack(alignment: .top, spacing: MemoraSpacing.md) {
                  AIPluginIconView(icon: plugin.icon)
                    .frame(width: 24)
                  VStack(alignment: .leading, spacing: 3) {
                    Text(plugin.name).font(.body)
                    if typeSize.isAccessibilitySize {
                      selectionLabel(plugin)
                    }
                    Text(plugin.state.reason ?? plugin.summary + " · " + plugin.cost.rawValue)
                      .font(.caption).foregroundStyle(.secondary)
                      .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                  }
                  if !typeSize.isAccessibilitySize {
                    Spacer(minLength: 4)
                    selectionLabel(plugin)
                  }
                }
                .padding(.horizontal, MemoraSpacing.lg).padding(.vertical, MemoraSpacing.md)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(MemoraPalette.secondaryBackground.opacity(selectedIDs.contains(plugin.id) ? 1 : 0))
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .accessibilityLabel("\(plugin.name)、\(plugin.state.label)")
              .accessibilityHint(plugin.state.reason ?? plugin.summary)
              .accessibilityAddTraits(selectedIDs.contains(plugin.id) ? .isSelected : [])
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxHeight: .infinity)
      .scrollDismissesKeyboard(.never)
    }
    // Bound the whole menu, not just its list: its header also grows with text.
    .frame(height: min(maximumHeight, max(100, CGFloat(candidates.count) * rowHeight + CGFloat(groups.count) * 28 + 45)))
    .background(MemoraPalette.elevated, in: RoundedRectangle(cornerRadius: MemoraRadius.card))
    .overlay { RoundedRectangle(cornerRadius: MemoraRadius.card).strokeBorder(MemoraPalette.border, lineWidth: 1) }
    .preservesComposerFocus()
    .accessibilityIdentifier("ai.mention.candidates")
    .accessibilityElement(children: .contain)
  }

  private func selectionLabel(_ plugin: AIPlugin) -> some View {
    Text(selectedIDs.contains(plugin.id) ? "選択済み" : plugin.state.isReady ? "追加" : plugin.state.label)
      .font(.caption).foregroundStyle(.secondary)
  }
}
