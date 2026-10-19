import SwiftUI

struct ComposerMentionStrip: View {
  @Environment(MemoraModel.self) private var model
  var mentions: [ComposerMention]
  var remove: (ComposerMention) -> Void
  @State private var inspectedPlugin: AIPlugin?

  var body: some View {
    let plugins = mentions.map { model.pluginInfo(for: $0) }
    ScrollView(.horizontal) {
      HStack(spacing: 8) {
        ForEach(mentions) { mention in
          let plugin = plugins.first { $0.id == mention.pluginID }
          let icon = plugin?.icon ?? AIPluginIcon.resolve(pluginID: mention.pluginID, name: mention.label)
          HStack(spacing: 0) {
            Button { inspectedPlugin = plugin } label: {
              HStack(spacing: 6) {
                AIPluginIconView(icon: icon)
                Text(mention.label).lineLimit(1)
              }
              .padding(.leading, 12).padding(.trailing, 4).frame(minHeight: 44)
              .contentShape(Rectangle())
            }
            .accessibilityLabel("\(mention.label)、\(plugin?.state.label ?? "指定した記録")、情報を表示")
            Button("\(mention.label)の指定を削除", icon: .xmark) { remove(mention) }
              .labelStyle(.iconOnly).frame(width: 44, height: 44).contentShape(Rectangle())
          }
          .font(.caption)
          .buttonStyle(.plain)
          .background(MemoraPalette.secondaryBackground, in: Capsule())
        }
      }
    }
    .scrollIndicators(.hidden)
    .scrollDismissesKeyboard(.never)
    .preservesComposerFocus()
    .sheet(item: $inspectedPlugin) { plugin in
      NavigationStack {
        Form {
          Section {
            Label(plugin.name, icon: plugin.icon.systemSymbol)
            Text(plugin.summary)
            LabeledContent("状態", value: plugin.state.label)
            LabeledContent("料金", value: plugin.cost.rawValue)
            if let reason = plugin.state.reason { Text(reason).font(.footnote) }
          }
          Section("権限") { ForEach(plugin.permissions, id: \.self) { Text($0) } }
        }
        .navigationTitle(plugin.name).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { ToolbarIconButton("閉じる", icon: .xmark) { inspectedPlugin = nil } } }
      }
    }
  }
}
