import SwiftUI

struct AIMemoryEditFields: View {
  @Binding var draft: AIMemoryEditDraft
  var related: [AIMemory]

  var body: some View {
    Section {
      TextField("覚えていること", text: $draft.text, axis: .vertical)
      Text("\(draft.text.count) / 200文字")
        .font(.caption).foregroundStyle(.secondary)
      Picker("種類", selection: $draft.kind) {
        ForEach(AIMemory.Kind.allCases, id: \.self) { Text($0.label).tag($0) }
      }
      Picker("状態", selection: $draft.status) {
        ForEach(AIMemory.Status.allCases, id: \.self) { Text($0.label).tag($0) }
      }
      Picker("機微情報", selection: $draft.sensitivity) {
        ForEach(AIMemory.Sensitivity.allCases, id: \.self) { Text($0.label).tag($0) }
      }
      TextField("項目名（例: 役割）", text: $draft.predicate)
    } header: {
      Text("内容")
    } footer: {
      Text("同じ項目名の有効な値が異なるときは「矛盾あり」として保持します。過去・未確認・矛盾・機微情報は自動利用しません。")
    }
    if !related.isEmpty {
      Section {
        ForEach(related) { memory in
          VStack(alignment: .leading, spacing: 4) {
            Text(memory.text)
            Text("\(memory.status.label) · \(memory.updatedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(Locale(identifier: "ja_JP"))))")
              .font(.caption).foregroundStyle(.secondary)
          }
          .accessibilityElement(children: .combine)
        }
        if draft.status == .current {
          Toggle("編集中の内容を現在の情報として確定", isOn: $draft.resolvesConflicts)
        }
      } header: {
        Text("同じ項目のほかの記憶")
      } footer: {
        Text("確定して保存すると、上の\(related.count)件を「過去の情報」に変更します。元の内容・出典・変更前の状態は残ります。項目名が「note」の記憶はまとめません。")
      }
    }
  }
}
