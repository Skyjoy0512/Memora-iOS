#if DEBUG
import SwiftUI

/// Uses production fields and edit plans with fictional values; no model or store is connected.
struct AIMemoryEditingExampleView: View {
  @State private var memories = Self.examples
  @State private var original = Self.examples[0]
  @State private var draft = AIMemoryEditDraft(memory: Self.examples[0])
  @State private var result = "未操作"

  var body: some View {
    let related = AIMemoryEditPlan.relatedMemories(in: memories, to: original, predicate: draft.predicate)
    MemoraForm {
      Section {
        Text("すべて架空の記憶です。この画面内だけで変更し、保存済みメモリやAIには接続しません。")
          .font(.footnote).foregroundStyle(.secondary)
      }
      AIMemoryEditFields(draft: $draft, related: related)
      Section("操作の確認") {
        Button("編集中の内容を保存") {
          if let candidate = draft.plan(for: original, related: related).applying(to: memories, workspaceID: nil),
             let updated = candidate.first(where: { $0.id == original.id }) {
            memories = candidate; original = updated
            draft = AIMemoryEditDraft(memory: original)
            result = "保存しました（画面内のみ）"
          } else {
            result = "内容が変わったため保存していません"
          }
        }
        .disabled(draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.text.count > 200)
        Button("別の編集による変更を再現") {
          memories[0].text = "ほかの画面で変更された架空の役割"
          result = "保存前の値が変わりました"
        }
        Button("架空の記憶をリセット") {
          memories = Self.examples; original = memories[0]
          draft = AIMemoryEditDraft(memory: original); result = "未操作"
        }
        Text(result).accessibilityLabel("編集の確認結果").accessibilityValue(result)
      }
      Section("現在の画面内データ") {
        ForEach(memories) { memory in
          VStack(alignment: .leading, spacing: 4) {
            Text(memory.text)
            Text("\(memory.status.label) · 変更履歴 \(memory.revisions?.count ?? 0)件")
              .font(.caption).foregroundStyle(.secondary)
          }.accessibilityElement(children: .combine)
        }
      }
    }
    .tint(.primary)
    .navigationTitle("記憶の更新を確認").navigationBarTitleDisplayMode(.inline)
  }

  private static let examples: [AIMemory] = {
    let date = Date(timeIntervalSince1970: 1_791_849_600)
    return ["新規事業のプロジェクト責任者", "営業担当"].map { text in
      AIMemory(id: UUID(), text: text, origin: .told, createdAt: date,
        semantic: .init(type: .role, predicate: "役割", value: text, sourceReference: "fixture",
          observedAt: date, updatedAt: date, validFrom: date, status: .conflicted))
    }
  }()
}
#endif
