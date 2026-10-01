import SwiftUI

/// What Ask AI remembers about the person: every entry can be read, edited
/// and deleted, and the whole memory can be turned off.
struct AIMemoryView: View {
  @Environment(MemoraModel.self) private var model
  @State private var isAdding = false
  @State private var newText = ""
  @State private var editing: AIMemory?
  @State private var editText = ""
  @State private var isConfirmingDeleteAll = false

  var body: some View {
    @Bindable var model = model

    List {
      Section {
        Toggle("メモリを使う", isOn: $model.isAIMemoryEnabled)
      } footer: {
        Text("オンのとき、Ask AIは下の内容と、関係しそうな過去の会話を参考に答えます。「〇〇を覚えておいて」と頼むと追加されます。")
      }

      Section {
        if model.aiMemories.isEmpty {
          Text("まだ何も覚えていません")
            .foregroundStyle(.secondary)
        } else {
          ForEach(model.aiMemories) { memory in
            Button {
              editText = memory.text
              editing = memory
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text(memory.text)
                  .foregroundStyle(.primary)
                Text("\(memory.origin == .agent ? "エージェントが提案" : "あなたが伝えた") · \(memory.createdAt.formatted(date: .abbreviated, time: .omitted))")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("タップして編集")
          }
          .onDelete { offsets in
            model.deleteAIMemories(Set(offsets.map { model.aiMemories[$0].id }))
          }
        }

        Button("追加", icon: .plus) {
          newText = ""
          isAdding = true
        }
      } header: {
        Text("覚えていること")
      } footer: {
        Text("この端末だけに保存されます。質問するときに、選んでいるAIへ一緒に送られます。")
      }

      if !model.aiMemories.isEmpty {
        Section {
          Button("すべて削除", role: .destructive) {
            isConfirmingDeleteAll = true
          }
        }
      }
    }
    .navigationTitle("メモリ")
    .navigationBarTitleDisplayMode(.inline)
    .alert("覚えてほしいこと", isPresented: $isAdding) {
      TextField("例: 営業部のマネージャー", text: $newText)
      Button("追加") { model.addAIMemory(newText, origin: .told) }
      Button("キャンセル", role: .cancel) {}
    } message: {
      Text("役割、好み、よく出てくる人のことなどを短く書きます。")
    }
    .alert("編集", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
      TextField("内容", text: $editText)
      Button("保存") {
        if let editing { model.updateAIMemory(editing.id, text: editText) }
      }
      Button("キャンセル", role: .cancel) {}
    } message: {
      Text("空にすると削除されます。")
    }
    .confirmationDialog("覚えていることをすべて削除しますか？", isPresented: $isConfirmingDeleteAll, titleVisibility: .visible) {
      Button("すべて削除", role: .destructive) { model.deleteAllAIMemories() }
      Button("キャンセル", role: .cancel) {}
    } message: {
      Text("元に戻せません。過去の会話の履歴は残ります。")
    }
  }
}
