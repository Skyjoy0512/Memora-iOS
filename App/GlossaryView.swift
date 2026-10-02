import SwiftUI

/// The words transcription should listen for and summaries should spell the
/// same way: company, product, service and people's names.
struct GlossaryView: View {
  @Environment(MemoraModel.self) private var model
  @State private var newTerm = ""
  @FocusState private var isFieldFocused: Bool

  var body: some View {
    let automatic = model.transcriptionVocabulary.filter { term in
      !model.glossaryTerms.contains { $0.caseInsensitiveCompare(term) == .orderedSame }
    }

    List {
      Section {
        HStack {
          TextField("例: 株式会社メモラ、Memora Plus", text: $newTerm)
            .focused($isFieldFocused)
            .submitLabel(.done)
            .onSubmit(add)
          Button("追加", action: add)
            .disabled(newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }

        ForEach(model.glossaryTerms, id: \.self) { term in
          Text(term)
        }
        .onDelete { model.removeGlossaryTerms(at: $0) }
      } header: {
        Text("用語")
      } footer: {
        Text("社名・製品名・サービス名・専門用語など。文字起こしで聞き取りやすくなり、要約の表記もこれに合わせます。")
      }

      if !automatic.isEmpty {
        Section {
          Text(automatic.joined(separator: "、"))
            .font(.subheadline)
            .foregroundStyle(.secondary)
        } header: {
          Text("自動で使う名前")
        } footer: {
          Text("「人物」と「プロジェクト」に登録した名前も一緒に使います。")
        }
      }
    }
    .navigationTitle("用語集")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if !model.glossaryTerms.isEmpty {
        EditButton()
      }
    }
  }

  private func add() {
    if model.addGlossaryTerm(newTerm) {
      newTerm = ""
    }
    isFieldFocused = true
  }
}
