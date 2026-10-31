import SwiftUI

struct MarketplaceDefinitionContent: View {
  var definition: MarketplaceDefinition
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      if let skill = definition.skill {
        Text("手順").font(.headline)
        Text(skill.instructions).font(.body)
        if !skill.toolNames.isEmpty {
          Text("利用するツール").font(.headline)
          ForEach(skill.toolNames, id: \.self) { Text($0).font(.caption.monospaced()) }
        }
      }
      if let template = definition.template {
        Text(template.usesPrompt ? "指示" : "まとめる項目").font(.headline)
        if template.usesPrompt { Text(template.prompt) }
        else { ForEach(template.sections, id: \.self) { Text($0) } }
        if !template.focus.isEmpty { Text(template.focus).font(.subheadline).foregroundStyle(.secondary) }
      }
    }.textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
  }
}
