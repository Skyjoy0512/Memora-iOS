import SwiftUI

/// What Ask AI remembers about the person: every entry can be read, edited
/// and deleted, and the whole memory can be turned off.
struct AIMemoryView: View {
  @Environment(MemoraModel.self) private var model
  @State private var isAdding = false
  @State private var newText = ""
  @State private var editing: AIMemory?
  @State private var query = ""
  @State private var isConfirmingDeleteAll = false
  @State private var operationWorkspaceID: String?
  @State private var failed = false

  var body: some View {
    @Bindable var model = model
    let memories = model.visibleAIMemories.filter { query.isEmpty || $0.text.localizedStandardContains(query) }

    MemoraForm {
      Section {
        Toggle("メモリを使う", isOn: $model.isAIMemoryEnabled)
      } footer: {
        Text("オンのとき、Ask AIは下の内容と、関係しそうな過去の会話を参考に答えます。「〇〇を覚えておいて」と頼むと追加されます。")
      }

      Section {
        if memories.isEmpty {
          Text(query.isEmpty ? "まだ何も覚えていません" : "一致する記憶はありません")
            .foregroundStyle(.secondary)
        } else {
          ForEach(memories) { memory in
            Button {
              editing = memory
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text(memory.text)
                  .foregroundStyle(.primary)
                Text("\(memory.status.label) · \(memory.updatedAt.formatted(date: .abbreviated, time: .omitted))")
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
            if !model.deleteAIMemories(Set(offsets.map { memories[$0].id })) { failed = true }
          }
        }

        Button("追加", icon: .plus) {
          newText = ""
          operationWorkspaceID = model.currentTeamID
          isAdding = true
        }
      } header: {
        Text("覚えていること")
      } footer: {
        Text("この端末に保存されます。「現在有効」で確認済みの通常の記憶だけを、質問に応じて選んだAIへ送ります。過去・未確認・矛盾・機微情報は自動利用しません。")
      }

      if !memories.isEmpty {
        Section {
          Button("すべて削除", role: .destructive) {
            operationWorkspaceID = model.currentTeamID
            isConfirmingDeleteAll = true
          }
        }
      }
    }
    .navigationTitle("メモリ")
    .navigationBarTitleDisplayMode(.inline)
    .alert("覚えてほしいこと", isPresented: $isAdding) {
      TextField("例: 営業部のマネージャー", text: $newText)
      Button("追加") {
        if operationWorkspaceID != model.currentTeamID || !model.addAIMemory(newText, origin: .told) { failed = true }
      }
      Button("キャンセル", role: .cancel) {}
    } message: {
      Text("役割、好み、よく出てくる人のことなどを短く書きます。")
    }
    .sheet(item: $editing) { memory in AIMemoryEditor(memory: memory) }
    .alert("変更できませんでした", isPresented: $failed) { Button("閉じる", role: .cancel) {} } message: {
      Text("空の内容・重複・保存上限、または保存先の状態を確認して再試行してください。今回の変更は保存していません。")
    }
    .searchable(text: $query, prompt: "記憶を検索")
    .confirmationDialog("覚えていることをすべて削除しますか？", isPresented: $isConfirmingDeleteAll, titleVisibility: .visible) {
      Button("すべて削除", role: .destructive) { if !model.deleteAllAIMemories(in: operationWorkspaceID) { failed = true } }
      Button("キャンセル", role: .cancel) {}
    } message: {
      Text("元に戻せません。過去の会話の履歴は残ります。")
    }
    .onChange(of: model.currentTeamID) {
      editing = nil; isAdding = false; isConfirmingDeleteAll = false; query = ""
    }
  }
}
