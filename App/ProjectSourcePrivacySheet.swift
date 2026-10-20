import SwiftUI

struct ProjectSourcePrivacySheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var source: ProjectSource
  @State private var privacy: RecordPrivacy

  init(source: ProjectSource) {
    self.source = source
    _privacy = State(initialValue: source.privacy)
  }

  var body: some View {
    NavigationStack {
      MemoraForm {
        Section {
          Picker("区分", selection: $privacy.classification) {
            ForEach(RecordPrivacy.Classification.allCases, id: \.self) { Text($0.title).tag($0) }
          }
          Toggle("外部AIでの参照を許可", isOn: $privacy.allowsCloudAI)
            .disabled(privacy.classification == .unknown)
        } footer: {
          Text("許可したソースの抽出本文を、質問時に選択中のAIへ送信します。画像の元データや音声はこのチャットから送信しません。")
        }
      }
      .navigationTitle("プライバシー").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("キャンセル", icon: .xmark) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("保存", icon: .checkmark) {
            guard var current = model.source(id: source.id) else { return }
            privacy.updatedAt = .now
            current.privacy = privacy
            if model.storeProjectSource(current) { dismiss() }
          }
        }
      }
    }
  }
}
