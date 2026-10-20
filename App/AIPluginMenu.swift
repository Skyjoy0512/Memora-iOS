import SwiftUI

struct AIPluginMenu: View {
  var candidates: [AIPlugin]
  var selectedIDs: Set<String> = []
  var maximumHeight: CGFloat
  var select: (AIPlugin) -> Void
  var cancel: () -> Void
  @State private var contentHeight: CGFloat = 0
  @State private var headerHeight: CGFloat = MemoraSpacing.touchTarget

  var body: some View {
    let groups = AIPlugin.Kind.allCases.compactMap { kind -> (AIPlugin.Kind, [AIPlugin])? in
      let rows = candidates.filter { $0.kind == kind }
      return rows.isEmpty ? nil : (kind, rows)
    }
    VStack(spacing: 0) {
      HStack {
        ViewThatFits(in: .horizontal) {
          Text("ツール・スキル・ソース").fixedSize(horizontal: true, vertical: true)
          Text("候補").accessibilityLabel("ツール・スキル・ソース")
        }
        .font(MemoraTypography.metadata).foregroundStyle(MemoraPalette.textSecondary)
        Spacer(minLength: 4)
        MemoraIconButton("候補を閉じる", icon: .xmark, action: cancel)
      }
      .padding(.horizontal, MemoraSpacing.md)
      .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
      Divider()
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          if candidates.isEmpty {
            Text("候補がありません")
              .font(.subheadline).foregroundStyle(.secondary).padding(MemoraSpacing.lg)
          }
          ForEach(groups, id: \.0) { kind, rows in
            Text(kind.rawValue)
              .font(MemoraTypography.metadata.weight(.medium))
              .foregroundStyle(MemoraPalette.textSecondary)
              .padding(.horizontal, MemoraSpacing.lg)
              .padding(.top, MemoraSpacing.lg)
              .padding(.bottom, MemoraSpacing.xs)
            ForEach(rows) { plugin in
              AIPluginMenuRow(plugin: plugin, isSelected: selectedIDs.contains(plugin.id)) {
                select(plugin)
              }
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
      }
      .frame(maxHeight: .infinity)
      .scrollDismissesKeyboard(.never)
      .scrollBounceBehavior(.basedOnSize)
    }
    // Bound the whole menu, not just its list: its header also grows with text.
    .frame(height: min(maximumHeight, max(100, headerHeight + contentHeight + 1)))
    .memoraGlass(in: RoundedRectangle(cornerRadius: MemoraRadius.card), backed: false)
    .preservesComposerFocus()
    .accessibilityIdentifier("ai.mention.candidates")
    .accessibilityElement(children: .contain)
  }

}
