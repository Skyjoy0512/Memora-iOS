import SwiftUI

struct AIPluginMenu: View {
  var candidates: [AIPlugin]
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
        Text("プラグインやファイルを検索")
          .font(.caption).foregroundStyle(.secondary)
        Spacer(minLength: 4)
        Button("候補を閉じる", icon: .xmark, action: cancel)
          .labelStyle(.iconOnly).frame(width: 44, height: 44)
      }
      .padding(.horizontal, 12)
      Divider()
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          if candidates.isEmpty {
            Text("候補がありません")
              .font(.subheadline).foregroundStyle(.secondary).padding(16)
          }
          ForEach(groups, id: \.0) { kind, rows in
            Text(kind.rawValue).font(.caption).foregroundStyle(.secondary)
              .padding(.horizontal, 14).padding(.top, 10)
            ForEach(rows) { plugin in
              Button { select(plugin) } label: {
                HStack(spacing: 10) {
                  Image(icon: plugin.kind == .file ? .docText : .plugsConnected)
                    .frame(width: 24)
                  VStack(alignment: .leading, spacing: 3) {
                    Text(plugin.name).font(.body)
                    Text(plugin.state.reason ?? plugin.summary)
                      .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                  }
                  Spacer(minLength: 4)
                  Text(plugin.state.isReady ? (plugin.kind == .file ? "ファイル" : "選択") : plugin.state.label)
                    .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .accessibilityLabel("\(plugin.name)、\(plugin.state.label)")
              .accessibilityHint(plugin.state.reason ?? plugin.summary)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(height: min(maximumHeight - 45, max(54, CGFloat(candidates.count) * rowHeight + CGFloat(groups.count) * 28)))
      .scrollDismissesKeyboard(.never)
    }
    .background(MemoraPalette.background, in: RoundedRectangle(cornerRadius: 16))
    .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(MemoraPalette.border, lineWidth: 1) }
    .accessibilityElement(children: .contain)
  }
}
