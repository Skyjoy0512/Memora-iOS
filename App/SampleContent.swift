import Foundation

enum SampleContent {
  static let productSpaceID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
  static let salesSpaceID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
  static let productMeetingID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
  static let oneOnOneMeetingID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
  static let salesMeetingID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!

  static let generatedTranscript = [
    TranscriptSegment(
      id: UUID(),
      speaker: "田中",
      speakerIsCertain: true,
      timestamp: 18,
      text: "次のリリースでは、録音を始めるまでの迷いをなくすことを最優先にしたいです。"
    ),
    TranscriptSegment(
      id: UUID(),
      speaker: "自分",
      speakerIsCertain: true,
      timestamp: 42,
      text: "賛成です。AIの設定を先に選ばせるのではなく、録音後に自動で整理される流れにしましょう。"
    ),
    TranscriptSegment(
      id: UUID(),
      speaker: "話者3",
      speakerIsCertain: false,
      timestamp: 78,
      text: "タスクには元の発言へ戻れるリンクがあると、担当者と期限を確認しやすそうです。"
    ),
    TranscriptSegment(
      id: UUID(),
      speaker: "田中",
      speakerIsCertain: true,
      timestamp: 116,
      text: "では初回録音フローを金曜日までに固めて、次の定例で確認しましょう。"
    )
  ]

  static func make() -> (meetings: [Meeting], spaces: [MemoraSpace], tasks: [MemoraTask]) {
    let spaces = [
      MemoraSpace(id: productSpaceID, name: "新規アプリ", symbol: "square.stack.3d.up"),
      MemoraSpace(id: salesSpaceID, name: "法人提案", symbol: "briefcase")
    ]

    let meetings = [
      Meeting(
        id: productMeetingID,
        title: "リリース方針レビュー",
        createdAt: Calendar.current.date(byAdding: .hour, value: -2, to: .now)!,
        duration: 2_634,
        source: .recording,
        status: .ready,
        summary: "次期リリースは、録音開始の速さと会議後の行動につながる体験を優先する方針で合意しました。",
        keyPoints: [
          "初回体験は説明より実際の録音を優先する",
          "処理中でも完成した文字起こしは利用できる"
        ],
        decisions: [
          "録音とタスク抽出を最優先で提供する",
          "会議データは既定で端末内に保存する"
        ],
        openQuestions: [
          "クラウド同期の提供時期とプラン"
        ],
        transcript: generatedTranscript,
        spaceID: productSpaceID,
        audioURL: nil
      ),
      Meeting(
        id: oneOnOneMeetingID,
        title: "佐藤さん 1on1",
        createdAt: Calendar.current.date(byAdding: .day, value: -1, to: .now)!,
        duration: 1_842,
        source: .recording,
        status: .partialFailure("議事録の生成だけ完了できませんでした"),
        summary: "文字起こしは利用できます。AIによる要約を再試行してください。",
        keyPoints: [],
        decisions: [],
        openQuestions: [],
        transcript: generatedTranscript,
        spaceID: nil,
        audioURL: nil
      ),
      Meeting(
        id: salesMeetingID,
        title: "Acme社 提案ヒアリング",
        createdAt: Calendar.current.date(byAdding: .day, value: -3, to: .now)!,
        duration: 3_186,
        source: .importFile,
        status: .ready,
        summary: "現場での議事録共有に時間がかかっており、発言根拠付きの要約と担当者別タスクが求められています。",
        keyPoints: [
          "毎週8件ほどの顧客会議を実施",
          "共有先は営業とカスタマーサクセス"
        ],
        decisions: [
          "次回はセキュリティ資料を含むデモを行う"
        ],
        openQuestions: [
          "社内保存期間の要件"
        ],
        transcript: generatedTranscript,
        spaceID: salesSpaceID,
        audioURL: nil
      )
    ]

    let tasks = [
      MemoraTask(
        id: UUID(),
        title: "初回録音フローの仕様を確定する",
        meetingID: productMeetingID,
        assignee: "自分",
        dueDate: Calendar.current.date(byAdding: .day, value: 2, to: .now),
        isCompleted: false
      ),
      MemoraTask(
        id: UUID(),
        title: "セキュリティ資料をAcme社へ送る",
        meetingID: salesMeetingID,
        assignee: "田中",
        dueDate: Calendar.current.date(byAdding: .day, value: 5, to: .now),
        isCompleted: false
      ),
      MemoraTask(
        id: UUID(),
        title: "要約テンプレートの候補を比較する",
        meetingID: productMeetingID,
        assignee: "自分",
        dueDate: Calendar.current.date(byAdding: .day, value: -1, to: .now),
        isCompleted: true
      )
    ]

    return (meetings, spaces, tasks)
  }
}
