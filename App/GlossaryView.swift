import SwiftUI

/// The words transcription should listen for and summaries should spell the
/// same way: company, product, service and people's names.
struct GlossaryView: View {
  @Environment(MemoraModel.self) private var model
  @State private var newTerm = ""
  @State private var isMailSuggestionsPresented = false
  @State private var gmail = GmailService.shared
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
            // A named action, so it reads 削除 rather than the system's
            // untranslated label.
            .swipeActions {
              Button("削除", icon: .trash, role: .destructive) {
                model.removeGlossaryTerm(term)
              }
            }
        }
      } header: {
        Text("用語")
      } footer: {
        Text("社名・製品名・サービス名・専門用語など。文字起こしで聞き取りやすくなり、要約の表記もこれに合わせます。")
      }

      Section {
        if gmail.isConnected {
          Button("メールから候補を集める", icon: .envelopeOpen) {
            isMailSuggestionsPresented = true
          }
        } else {
          NavigationLink {
            GmailSettingsView()
          } label: {
            Label("Gmailを連携して候補を集める", icon: .envelopeOpen)
          }
        }
      } footer: {
        Text("やりとりしている相手の名前、会社名、よく出てくる製品・サービス名を、最近のメールから見つけます。")
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
    .sheet(isPresented: $isMailSuggestionsPresented) {
      GlossaryMailSuggestionsView()
    }
  }

  private func add() {
    if model.addGlossaryTerm(newTerm) {
      newTerm = ""
    }
    isFieldFocused = true
  }
}
