import SwiftUI

struct RecordPrivacySettingsView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var target: RecordPrivacyTarget
  @State private var draft = RecordPrivacy()
  @State private var isSaving = false
  @State private var failure: String?

  init(meetingID: UUID) { target = .meeting(meetingID) }
  init(target: RecordPrivacyTarget) { self.target = target }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("機密区分", selection: Binding {
            draft.classification
          } set: { classification in
            guard classification != draft.classification else { return }
            draft.classification = classification
            draft.revokeExternalPermissions()
          }) {
            ForEach(RecordPrivacy.Classification.allCases.filter {
              $0.rank >= model.minimumPrivacyClassification(for: target).rank
            }, id: \.self) { Text($0.title).tag($0) }
          }
        } footer: {
          Text("未判定の記録は自動送信しません。顧客・医療・介護・未成年者の情報は慎重に扱ってください。")
        }
        Section("外部送信の許可") {
          Toggle("クラウドAIでの利用", isOn: $draft.allowsCloudAI)
          Toggle("常駐AIによる自動アクセス", isOn: $draft.allowsAutomaticAgentAccess)
            .disabled(!draft.allowsCloudAI)
          if model.supportsWebhookPermission(target) {
            Toggle("Webhookの自動送信", isOn: $draft.allowsAutomaticWebhook)
          }
          if model.supportsTeamPermission(target) {
            Toggle(teamPermissionLabel, isOn: $draft.allowsTeamSharing)
          }
        }
        .disabled(draft.classification == .unknown || !model.cloudReadingIsAvailable(for: target))
        Section {
          Text("今回だけクラウド要約を実行する送信確認とは別の設定です。過去の機密形式・用途による保護は一般テンプレートへの変更でも解除しません。声の特徴量は送信しません。")
            .foregroundStyle(.secondary)
          if !model.cloudReadingIsAvailable(for: target) {
            Text("位置情報・自動検出した移動や滞在は外部AIへ送信しません。")
          } else if case .meeting = target {} else {
            Text("元の録音に関連する記録は、元の録音の許可も必要です。タスクの元の会議を変更すると、そのタスクの外部利用許可は解除されます。")
          }
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
              if await model.setRecordPrivacy(draft, target: target) { dismiss() }
              else { failure = "保存できませんでした。保存状態を確認して再試行してください。" }
              isSaving = false
            }
          }
          .disabled(isSaving || !model.cloudReadingIsAvailable(for: target))
        }
      }
      .onAppear { draft = model.privacy(for: target) ?? RecordPrivacy() }
    }
  }

  private var teamPermissionLabel: String {
    if case .journal = target { return "元の録音のチーム用パッケージに含める" }
    return "チーム共有"
  }
}
