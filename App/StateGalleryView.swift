import SwiftUI

struct StateGalleryView: View {
  @Environment(MemoraModel.self) private var model
  var body: some View {
    List {
      #if DEBUG
      Section("表示（架空データ）") {
        NavigationLink("Loading・本文表示を確認") { MotionLoadingGalleryView() }
        NavigationLink("資料・メールの出典表示を確認") { ArtifactSourcesExampleView() }
      }
      Section("システム導線（遷移の確認）") {
        Button("Ask AIのリンクを開く") { openLink(.askAI) }
        Button("今日のタスクのリンクを開く") { openLink(.todayTasks) }
        Button("ジャーナルのリンクを開く") { openLink(.journal) }
        Button("メモ作成のリンクを開く") { openLink(.newMemo) }
      }
      #endif
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

      Section {
        #if DEBUG
        NavigationLink("構造化回答（表示の確認）") { NativeAIInterfaceExampleView() }
        NavigationLink("タスク候補（編集の確認）") { AgentTaskDraftExampleView() }
        NavigationLink("タスク候補（承認と保存の検証）") { AgentTaskOperationCheckView() }
        NavigationLink("Officeソース（取込と保存の検証）") { ProjectSourceOperationCheckView() }
        NavigationLink("関連タスク（範囲と保存の検証）") { ProjectTaskOperationCheckView() }
        #endif
        NavigationLink("Ask AIの経過（表示の確認）") {
          ScrollView {
            VStack(alignment: .leading, spacing: 32) {
              ThinkingTraceView(message: Self.demoTraceWorking)
            }
            .padding(18)
          }
        }
        NavigationLink("プロジェクトの提案（表示の確認）") {
          ScrollView {
            ProjectSuggestionCard(meeting: Self.demoMeeting, suggestions: Self.demoSuggestions)
              .padding(18)
          }
        }
        NavigationLink("エージェントからの質問（表示の確認）") {
          ScrollView {
            AgentQuestionCard(request: Self.demoQuestions)
              .padding(18)
          }
        }
      } header: {
        Text("Ask AI")
      } footer: {
        Text("表示確認はデモです。承認と保存の検証はローカルの検証タスクだけを扱います。モデル・外部APIは使いません。")
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

  #if DEBUG
  private func openLink(_ link: MemoraAppLink) {
    model.isSettingsPresented = false
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(350))
      guard !Task.isCancelled else { return }
      await model.handle(link.url)
    }
  }
  #endif
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

extension StateGalleryView {
  /// Questions that are only drawn, for checking the card.
  static let demoQuestions = AgentQuestionRequest(
    messageID: UUID(),
    questions: [
      AgentQuestion(text: "どの会議のフォローアップですか？", allowsMultiple: false, options: ["通話（9/30）", "WeeklySync（9/29）"]),
      AgentQuestion(text: "メールに入れる内容は？", allowsMultiple: true, options: ["決まったこと", "次にすること", "未決事項"]),
      AgentQuestion(text: "宛先はどなたですか？", allowsMultiple: false, options: ["Tanakaさん", "参加者全員"])
    ]
  )
}

extension StateGalleryView {
  /// A record that is only drawn, for checking the suggestion card.
  static let demoMeeting = Meeting(
    id: UUID(), title: "週次定例", createdAt: .now, duration: 1_800, source: .recording,
    status: .ready, summary: "", keyPoints: [], decisions: [], openQuestions: [],
    transcript: [], spaceID: nil, audioURL: nil
  )

  static let demoSuggestions = [
    ProjectSuggestion(
      space: MemoraSpace(id: UUID(), name: "WeeklySync", symbol: "folder"),
      signal: 3,
      reasons: ["同じカレンダーの定例の記録が入っています", "Tanakaさんの記録が入っています"]
    ),
    ProjectSuggestion(
      space: MemoraSpace(id: UUID(), name: "新規事業", symbol: "folder"),
      signal: 2,
      reasons: ["Satoさんの記録が入っています", "会議名にプロジェクト名が含まれています"]
    )
  ]
}

extension StateGalleryView {
  /// A reply still being formed, only drawn, for checking the status line.
  static let demoTraceWorking: AIChatMessage = {
    var message = AIChatMessage(role: .assistant, text: "", isThinking: true)
    message.isAgentReply = true
    message.createdAt = .now.addingTimeInterval(-3)
    message.agentSteps = [
      AgentStep(icon: .magnifyingglass, title: "記録を検索", detail: "記録1件", state: .done, query: "定例"),
      AgentStep(icon: .docText, title: "「WeeklySync」を読む")
    ]
    return message
  }()
}
