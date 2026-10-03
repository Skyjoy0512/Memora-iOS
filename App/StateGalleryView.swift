import SwiftUI

struct StateGalleryView: View {
  var body: some View {
    List {
      if FeatureFlags.isCallingEnabled {
        Section {
          NavigationLink("通話の設定（表示の確認）") {
            CallIntroView {}
          }
          NavigationLink("通話の説明と録音の同意") {
            CallExplanationView {}
          }
          NavigationLink("電話番号の登録") {
            PhoneNumberEntryView { _ in }
          }
          NavigationLink("番号の確認") {
            PhoneVerificationView(phoneNumber: "+819012345678") {}
          }
          NavigationLink("確認できました") {
            CallVerifiedView {}
          }
          NavigationLink("連絡先をつなぐ") {
            ConnectContactsView {}
          }
          NavigationLink("通話中の画面（デモ）") {
            ActiveCallView(session: Self.demoCall) {}
          }
        } header: {
          Text("通話")
        } footer: {
          Text("通話サービスが未接続でも画面を確認できます。通話中の画面はデモの表示で、電話はかかりません。")
        }
      }

      Section("権限と録音") {
        StateExampleRow(
          symbol: .micSlash,
          title: "マイクを使えません",
          detail: "設定を開く · 録音以外は利用可能",
          tint: .red
        )
        StateExampleRow(
          symbol: .exclamationmarkTriangle,
          title: "録音を開始できませんでした",
          detail: "入力を確認して再試行",
          tint: .orange
        )
      }

      Section("読み込みと処理") {
        StateExampleRow(
          symbol: .arrowDownDoc,
          title: "音声を読み込み中",
          detail: "62% · 完了後は未処理のまま保存",
          tint: .primary,
          progress: 0.62
        )
        StateExampleRow(
          symbol: .waveformBadgePlus,
          title: "文字起こし待ち",
          detail: "開始するまでAI利用は発生しません",
          tint: .secondary
        )
        StateExampleRow(
          symbol: .sparkles,
          title: "要約待ち",
          detail: "テンプレートを選んで手動生成",
          tint: .secondary
        )
        StateExampleRow(
          symbol: .textBubble,
          title: "文字起こし中",
          detail: "完成した発言から利用可能",
          tint: .primary,
          progress: 0.38
        )
        StateExampleRow(
          symbol: .exclamationmarkTriangle,
          title: "AI整理だけ未完了",
          detail: "文字起こしはそのまま利用できます",
          tint: .orange
        )
      }

      Section("接続と設定") {
        StateExampleRow(
          symbol: .wifiSlash,
          title: "ネットワークに接続できません",
          detail: "ローカル処理は継続 · AI整理は後で再試行",
          tint: .orange
        )
        StateExampleRow(
          symbol: .key,
          title: "APIキーが未設定です",
          detail: "Memoraの自動設定を使うか、設定で追加",
          tint: .secondary
        )
      }

      Section("Empty") {
        StateExampleRow(
          symbol: .waveform,
          title: "会議が0件",
          detail: "録音または音声インポートへ案内",
          tint: .primary
        )
        StateExampleRow(
          symbol: .checkmarkSquare,
          title: "タスクが0件",
          detail: "会話から見つかると自動で集約",
          tint: .primary
        )
        StateExampleRow(
          symbol: .sparkles,
          title: "AI履歴が0件",
          detail: "質問例から最初の検索へ案内",
          tint: .primary
        )
      }
    }
    .navigationTitle("状態と復旧")
    .memoraBackButton()
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct StateExampleRow: View {
  var symbol: MemoraIcon
  var title: String
  var detail: String
  var tint: Color
  var progress: Double?

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(icon: symbol)
        .font(.body.weight(.semibold))
        .foregroundStyle(tint)
        .frame(width: 28)
      VStack(alignment: .leading, spacing: 5) {
        Text(title)
          .font(.body.weight(.medium))
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
        if let progress {
          ProgressView(value: progress)
            .tint(tint)
        }
      }
    }
    .padding(.vertical, 5)
  }
}

extension StateGalleryView {
  /// A call that is only drawn, never connected, for checking the screen.
  @MainActor static let demoCall: PhoneCallSession = {
    let session = PhoneCallSession(number: "+819012345678", contactName: "田中さん")
    session.startedAt = .now
    return session
  }()
}
