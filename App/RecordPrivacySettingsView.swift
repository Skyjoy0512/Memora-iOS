import SwiftUI

struct RecordPrivacySettingsView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var meetingID: UUID
  @State private var draft = RecordPrivacy()
  @State private var isSaving = false
  @State private var failure: String?

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("機密区分", selection: $draft.classification) {
            ForEach(RecordPrivacy.Classification.allCases.filter {
              $0.rank >= (model.meeting(id: meetingID)?.minimumPrivacyClassification.rank ?? 0)
            }, id: \.self) { Text($0.title).tag($0) }
          }
        } footer: {
          Text("未判定の記録は自動送信しません。顧客・医療・介護・未成年者の情報は慎重に扱ってください。")
        }
        Section("外部送信の許可") {
          Toggle("クラウドAIでの利用", isOn: $draft.allowsCloudAI)
          Toggle("常駐AIによる自動アクセス", isOn: $draft.allowsAutomaticAgentAccess)
            .disabled(!draft.allowsCloudAI)
          Toggle("Webhookの自動送信", isOn: $draft.allowsAutomaticWebhook)
          Toggle("チーム共有", isOn: $draft.allowsTeamSharing)
        }
        .disabled(draft.classification == .unknown)
        Section {
          Text("今回だけクラウド要約を実行する送信確認とは別の設定です。過去の機密形式・用途による保護は一般テンプレートへの変更でも解除しません。声の特徴量は送信しません。")
            .foregroundStyle(.secondary)
          if let failure { Text(failure).foregroundStyle(.red) }
        }
      }
      .disabled(isSaving)
      .navigationTitle("プライバシーと外部送信")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() }.disabled(isSaving) }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
            isSaving = true
            Task {
              if await model.setRecordPrivacy(draft, meetingID: meetingID) { dismiss() }
              else { failure = "保存できませんでした。保存状態を確認して再試行してください。" }
              isSaving = false
            }
          }
          .disabled(isSaving)
        }
      }
      .onAppear { draft = model.meeting(id: meetingID)?.effectivePrivacy ?? RecordPrivacy() }
    }
  }
}
