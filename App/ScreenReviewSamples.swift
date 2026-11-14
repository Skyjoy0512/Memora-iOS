import Foundation

/// Fixed identities keep an explicitly added display set removable and repeatable.
enum ScreenReviewSamples {
  static let spaceID = id(100)
  static let personID = id(101)
  static let historyID = id(501)
  static let meetingIDs = Set((1...8).map(id))
  static let documentIDs = Set([id(401), id(402)])
  static let taskIDs = Set([id(301), id(302)])
  static let journalIDs = Set((201...208).map(id))

  static func id(_ value: Int) -> UUID {
    UUID(uuidString: "A8E50000-0000-4000-8000-" + String(format: "%012X", value))!
  }

  static func meetings(at date: Date = .now) -> [Meeting] {
    let states: [(String, MeetingStatus, [TranscriptSegment])] = [
      ("文字起こし前", .waitingForTranscription, []),
      ("要約前", .waitingForSummary, SampleContent.generatedTranscript),
      ("取り込み中", .importing(0.4), []),
      ("文字起こし中", .transcribing(0.35), Array(SampleContent.generatedTranscript.prefix(2))),
      ("要約中", .organizing("要約を作成しています"), SampleContent.generatedTranscript),
      ("要約済み", .ready, SampleContent.generatedTranscript),
      ("文字起こし失敗", .failed("文字起こしを完了できませんでした（表示用サンプル）。"), []),
      ("要約失敗", .partialFailure("要約を完了できませんでした（表示用サンプル）。文字起こしは残っています。"), SampleContent.generatedTranscript)
    ]
    return states.enumerated().map { offset, state in
      var meeting = Meeting(id: id(offset + 1), title: "\(String(format: "%02d", offset + 1)) \(state.0)（サンプル）",
        createdAt: date.addingTimeInterval(-Double(offset) * 180), duration: 720,
        source: offset.isMultiple(of: 2) ? .importFile : .recording, status: state.1,
        summary: offset == 5 ? SummarizedAudioSample.make().summary : "",
        keyPoints: [], decisions: [], openQuestions: [], transcript: state.2, spaceID: spaceID)
      meeting.participantIDs = [personID]
      meeting.notes = "画面確認用の架空データです。音声ファイルは含みません。処理中の表示は固定され、音声処理やAI送信は開始しません。\n\n確認メモ：タイトル・日時・本文・下部のAsk AI入力欄を確認してください。"
      return meeting
    }
  }

  static func journal(for meetings: [Meeting]) -> [LifeLogEntry] {
    meetings.enumerated().map { offset, meeting in
      LifeLogEntry(id: id(201 + offset), createdAt: meeting.createdAt, title: meeting.title,
        summary: "画面確認用のサンプルです。記録を開いて要約・文字起こし・ノートを確認できます。",
        source: .iphone, meetingID: meeting.id, kind: .event, eventDate: meeting.createdAt)
    }
  }

  static func tasks(at date: Date = .now) -> [MemoraTask] {
    [MemoraTask(id: id(301), title: "サンプル：文字起こしと要約の画面を確認する", meetingID: id(6),
      assignee: "自分", dueDate: date, isCompleted: false),
     MemoraTask(id: id(302), title: "サンプル：一覧の読みやすさを確認する", meetingID: id(6),
      assignee: nil, dueDate: nil, isCompleted: true)]
  }

  static func documents() -> [MemoraDocument] {
    [MemoraDocument(id: id(401), title: "画面確認の資料（サンプル）", kind: .document,
      markdown: "# 画面確認\n\n表示用の架空資料です。AIで生成した結果ではありません。\n\n## 確認する画面\n\n- 文字起こし前・要約前\n- 処理中・失敗・要約済み\n- ジャーナル・タスク・資料\n\n| 項目 | 確認内容 |\n| --- | --- |\n| 文字 | 折り返しと行間 |\n| 操作 | 下部の入力欄とメニュー |", spaceID: spaceID),
     MemoraDocument(id: id(402), title: "画面確認のスライド（サンプル）", kind: .slides,
      slides: [DocumentSlide(title: "画面確認用サンプル", bullets: [], notes: "架空の表示データです。"),
        DocumentSlide(title: "状態別の記録", bullets: ["文字起こし前・要約前", "処理中・失敗・完了"], notes: "実際の処理は開始しません。")], spaceID: spaceID)]
  }

  static func history(at date: Date = .now) -> AIConversationEntry {
    AIConversationEntry(id: historyID, question: "画面確認用の会話（サンプル）",
      answer: "これは表示確認用に用意した架空の回答です。AIへの送信は行っていません。\n\n文字起こし前・要約前・処理中・失敗・完了の記録を、ライブラリやプロジェクトから開いて確認できます。",
      scopeLabel: "画面確認（サンプル）", engineLabel: "表示用サンプル・AI未使用", createdAt: date)
  }
}
