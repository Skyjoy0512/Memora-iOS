import SwiftUI

struct MarketplaceDefinitionContent: View {
  var definition: MarketplaceDefinition
  var body: some View {
    VStack(alignment: .leading, spacing: MemoraSpacing.lg) {
      if let skill = definition.skill {
        Text("使い方").font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
        Text(skill.instructions).memoraReadingText()
        if !skill.toolNames.isEmpty {
          Text("利用するツール").font(.headline)
          ForEach(skill.toolNames, id: \.self) { Text($0).font(.caption.monospaced()) }
        }
      }
      if let template = definition.template {
        Text(template.usesPrompt ? "プロンプト" : "まとめる項目").font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
        if template.usesPrompt { Text(template.prompt).memoraReadingText() }
        else { ForEach(template.sections, id: \.self) { Text($0) } }
        if !template.focus.isEmpty { Text(template.focus).font(.subheadline).foregroundStyle(.secondary) }
      }
    }.textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
  }
}
