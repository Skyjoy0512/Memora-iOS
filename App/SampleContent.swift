import Foundation

enum SampleContent {
  static let productSpaceID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
  static let salesSpaceID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
  static let productMeetingID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
  static let oneOnOneMeetingID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
  static let salesMeetingID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
  static let designMeetingID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
  static let weeklyMeetingID = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
  static let interviewMeetingID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
  static let ideaMeetingID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
  static let importedWaitingMeetingID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!

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

  static func makeLifeLog() -> [LifeLogEntry] {
    let calendar = Calendar.current
    return [
      LifeLogEntry(
        id: UUID(),
        createdAt: calendar.date(bySettingHour: 8, minute: 35, second: 0, of: .now) ?? .now,
        title: "朝のアイデアメモ",
        summary: "移動中に思いついた、録音開始までの迷いを減らす方法。",
        source: .omi,
        meetingID: nil,
        kind: .memo
      ),
      LifeLogEntry(
        id: UUID(),
        createdAt: calendar.date(bySettingHour: 11, minute: 40, second: 0, of: .now) ?? .now,
        title: "チームとの立ち話",
        summary: "次の検証では、会議後すぐにタスクへ移れる流れを確認する。",
        source: .omi,
        meetingID: nil,
        kind: .event,
        eventDate: calendar.date(bySettingHour: 11, minute: 40, second: 0, of: .now)
      ),
      LifeLogEntry(
        id: UUID(),
        createdAt: calendar.date(bySettingHour: 16, minute: 5, second: 0, of: .now) ?? .now,
        title: "リリース方針レビュー",
        summary: "録音の速さと、次の行動につながる整理を優先する。",
        source: .iphone,
        meetingID: productMeetingID,
        kind: .event,
        eventDate: calendar.date(bySettingHour: 16, minute: 5, second: 0, of: .now)
      ),
      LifeLogEntry(
        id: UUID(),
        createdAt: calendar.date(bySettingHour: 7, minute: 52, second: 0, of: .now) ?? .now,
        title: "渋谷駅に到着",
        summary: "朝の移動を記録しました。",
        source: .iphone,
        meetingID: nil,
        kind: .location,
        locationName: "渋谷駅"
      )
    ]
  }

  static func make() -> (meetings: [Meeting], spaces: [MemoraSpace], tasks: [MemoraTask]) {
    let spaces = [
      MemoraSpace(id: productSpaceID, name: "新規アプリ", symbol: "square.stack.3d.up"),
      MemoraSpace(id: salesSpaceID, name: "法人提案", symbol: "briefcase")
    ]

    let meetings = [
      Meeting(
        id: importedWaitingMeetingID,
        title: "顧客インタビュー音声",
        createdAt: Calendar.current.date(byAdding: .hour, value: -1, to: .now)!,
        duration: 2_106,
        source: .importFile,
        status: .waitingForTranscription,
        summary: "音声を保存しました。必要な時に文字起こしを開始できます。",
        keyPoints: [],
        decisions: [],
        openQuestions: [],
        transcript: [],
        spaceID: nil,
        audioURL: nil
      ),
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
      ),
      Meeting(
        id: designMeetingID,
        title: "デザインレビュー",
        createdAt: Calendar.current.date(byAdding: .day, value: -5, to: .now)!,
        duration: 2_246,
        source: .recording,
        status: .ready,
        summary: "会議一覧は装飾を抑え、過去の内容を短時間で読み返せる密度を優先します。質問は閲覧中の文脈を保ったまま入力でき、主要操作は画面下部へまとめる方針です。",
        keyPoints: [
          "会議の要約を一覧から3行まで確認できるようにする",
          "プロジェクトは分類が必要になった時だけ使えるようにする"
        ],
        decisions: ["メインカラーは黒を基調にする"],
        openQuestions: ["長いプロジェクト名の表示方法"],
        transcript: generatedTranscript,
        spaceID: productSpaceID,
        audioURL: nil
      ),
      Meeting(
        id: weeklyMeetingID,
        title: "週次プロダクト定例",
        createdAt: Calendar.current.date(byAdding: .day, value: -7, to: .now)!,
        duration: 3_582,
        source: .recording,
        status: .ready,
        summary: "ベータ版の主要フローは予定どおり進行しています。文字起こしの部分成功を保持し、AI整理が失敗した場合でも会議内容を失わず再試行できる状態を次の検証対象にしました。",
        keyPoints: ["処理状態はユーザーの言葉で簡潔に伝える"],
        decisions: ["部分成功をMVPから正式に扱う"],
        openQuestions: ["再試行の自動実行条件"],
        transcript: generatedTranscript,
        spaceID: productSpaceID,
        audioURL: nil
      ),
      Meeting(
        id: interviewMeetingID,
        title: "ユーザーインタビュー #08",
        createdAt: Calendar.current.date(byAdding: .day, value: -10, to: .now)!,
        duration: 2_918,
        source: .importFile,
        status: .ready,
        summary: "参加者は会議直後に要約を共有し、その後必要な発言だけを確認しています。音声の聞き直しより、決定事項と担当タスクへすぐ移れることに最も強い価値を感じていました。",
        keyPoints: ["要約から原文へ戻れる根拠表示が重要"],
        decisions: [],
        openQuestions: ["外部タスク管理サービスとの連携"],
        transcript: generatedTranscript,
        spaceID: nil,
        audioURL: nil
      ),
      Meeting(
        id: ideaMeetingID,
        title: "移動中のアイデアメモ",
        createdAt: Calendar.current.date(byAdding: .day, value: -14, to: .now)!,
        duration: 746,
        source: .recording,
        status: .ready,
        summary: "会議だけでなく一人の音声メモも、考えの断片を次の行動へ変える素材として同じ流れで扱います。記録後の分類は自動化し、ユーザーに事前設定を求めない方針です。",
        keyPoints: ["短い音声メモも会議と同じ知識モデルへ統合する"],
        decisions: ["録音前の種類選択は設けない"],
        openQuestions: [],
        transcript: generatedTranscript,
        spaceID: nil,
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
