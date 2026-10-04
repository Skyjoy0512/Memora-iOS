import Foundation

/// The tools the Ask AI agent may call. Reading tools run straight away; a tool
/// that changes something waits for the person's approval first.
enum AgentTool: String, CaseIterable {
  case searchRecords = "search_records"
  case readRecord = "read_record"
  case listProjects = "list_projects"
  case listTasks = "list_tasks"
  case readPerson = "read_person"
  case createDocument = "create_document"
  case createSlides = "create_slides"
  case addTasks = "add_tasks"
  case createProject = "create_project"
  case moveRecordsToProject = "move_records_to_project"
  case addJournalMemo = "add_journal_memo"
  case createCalendarEvent = "create_calendar_event"
  case draftEmail = "draft_email"
  case saveToNotion = "save_to_notion"
  case saveMemory = "save_memory"
  case searchEmail = "search_email"
  case readEmail = "read_email"
  case askUser = "ask_user"

  /// The tools offered right now: mail only while Gmail is connected, so the
  /// model is never handed a tool that cannot work.
  @MainActor
  static var offered: [AgentTool] {
    allCases.filter { !$0.needsGmail || GmailService.shared.isConnected }
  }

  @MainActor
  static var offeredOnDevice: [AgentTool] {
    onDeviceTools.filter { !$0.needsGmail || GmailService.shared.isConnected }
  }

  /// What a resident agent may use while it works unattended: reading only,
  /// and no questions, since nobody may be there to answer.
  @MainActor
  static var residentTools: [AgentTool] {
    offered.filter { !$0.needsApproval && $0 != .askUser }
  }

  var needsGmail: Bool {
    self == .searchEmail || self == .readEmail
  }

  /// The tools offered to the on-device model. Its context is small, so the
  /// long-form writers (slides) and the rarer organising tools stay with the
  /// cloud models.
  static let onDeviceTools: [AgentTool] = [
    .searchRecords, .readRecord, .readPerson, .listTasks, .addTasks, .createDocument,
    .createProject, .addJournalMemo, .createCalendarEvent, .draftEmail, .searchEmail, .readEmail
  ]

  /// True for tools that change the person's data.
  var needsApproval: Bool {
    switch self {
    case .searchRecords, .readRecord, .readPerson, .listProjects, .listTasks, .searchEmail, .readEmail, .askUser: false
    default: true
    }
  }

  /// The icon a step or approval card for this tool is drawn with.
  var icon: MemoraIcon {
    switch self {
    case .searchRecords: .magnifyingglass
    case .readRecord: .docText
    case .listProjects, .moveRecordsToProject: .folder
    case .listTasks, .addTasks: .checklist
    case .readPerson: .person
    case .createDocument: .docRichtext
    case .createSlides: .rectangleOnRectangleAngled
    case .createProject: .folderBadgePlus
    case .addJournalMemo: .squareAndPencil
    case .createCalendarEvent: .calendarBadgePlus
    case .draftEmail: .envelope
    case .saveToNotion: .notionLogo
    case .saveMemory: .brainHeadProfile
    case .searchEmail, .readEmail: .envelopeOpen
    case .askUser: .questionmarkBubble
    }
  }

  var summary: String {
    switch self {
    case .searchRecords:
      "会議の記録とジャーナルをキーワードで検索し、id・タイトル・日付・概要を返す。空のqueryなら新しい順。"
    case .readRecord:
      "search_recordsで得たidの記録を読む。会議なら要約・決定事項・タスク・文字起こしを返す。"
    case .listProjects:
      "プロジェクトの一覧（id・名前・記録の数）を返す。"
    case .listTasks:
      "タスクの一覧（タイトル・担当・期限・元の会議）を返す。"
    case .readPerson:
      "人物について、一緒の会議・その人が引き受けたタスク・一緒に決めたこと・最後に会った日を返す。nameが空なら登録済みの人の一覧。「〇〇さんと何を話した？」「約束は？」に使う。"
    case .createDocument:
      "Markdownの資料を作成して保存する（利用者の承認後に実行）。見出し・箇条書き・表で構成する。"
    case .createSlides:
      "スライド資料を作成して保存する（利用者の承認後に実行）。PowerPointとPDFで書き出せる。1枚目は箇条書きなしの表紙にできる。"
    case .addTasks:
      "タスクを追加する（利用者の承認後に実行）。"
    case .createProject:
      "プロジェクトを作成してidを返す（利用者の承認後に実行）。"
    case .moveRecordsToProject:
      "会議の記録をプロジェクトへ移動する（利用者の承認後に実行）。"
    case .addJournalMemo:
      "ジャーナルにメモを追加する（利用者の承認後に実行）。"
    case .createCalendarEvent:
      "カレンダーに予定を登録する（利用者の承認後に実行）。次回の会議や締め切りに使う。"
    case .draftEmail:
      "メールの下書きを作って開く（利用者の承認後）。宛先が分からなくても呼ぶ（宛先は利用者が入れる）。送信は利用者が行う。"
    case .saveToNotion:
      "会議の記録をNotionのページとして保存する（利用者の承認後に実行）。"
    case .saveMemory:
      "利用者について今後の会話でも使うこと（役割・好み・関係者など）を覚える（利用者の承認後に実行）。利用者が伝えたことだけ。"
    case .searchEmail:
      "利用者のGmailをGmailの検索構文で検索し、id・差出人・件名・日時・冒頭を返す。例: from:tanaka newer_than:7d、subject:見積"
    case .readEmail:
      "search_emailで得たidのメールの本文を読む。"
    case .askUser:
      "作業に必要なことが記録から分からないときだけ、利用者に質問する（1〜3問、各2〜5個の選択肢）。利用者は自由に書いても答えられる。推測で進めると間違えるときに使う。"
    }
  }

  /// The JSON schema of the tool's input.
  var inputSchema: [String: Any] {
    switch self {
    case .searchRecords:
      return object([
        "query": string("検索語。空白区切りで複数可"),
        "limit": ["type": "integer", "description": "最大件数（1〜20、既定8）"]
      ], required: ["query"])
    case .readRecord:
      return object(["id": string("記録のid")], required: ["id"])
    case .listProjects:
      return object([:], required: [])
    case .listTasks:
      return object([
        "include_completed": ["type": "boolean", "description": "完了済みも含めるか"]
      ], required: [])
    case .readPerson:
      return object(["name": string("人の名前（敬称なしでよい）。空なら一覧")], required: ["name"])
    case .createDocument:
      return object([
        "title": string("資料のタイトル"),
        "markdown": string("本文（Markdown）。タイトルの見出しは含めない"),
        "project_id": string("入れるプロジェクトのid（任意）")
      ], required: ["title", "markdown"])
    case .createSlides:
      return object([
        "title": string("スライド資料のタイトル"),
        "slides": [
          "type": "array",
          "description": "スライド。1枚の要点は3〜6個、各30字程度まで",
          "items": object([
            "title": string("スライドの見出し"),
            "bullets": ["type": "array", "items": ["type": "string"], "description": "要点"],
            "notes": string("話す内容のメモ（任意）")
          ], required: ["title", "bullets"])
        ],
        "project_id": string("入れるプロジェクトのid（任意）")
      ], required: ["title", "slides"])
    case .addTasks:
      return object([
        "tasks": [
          "type": "array",
          "items": object([
            "title": string("タスクの内容"),
            "assignee": string("担当者（記録で明言された場合のみ）"),
            "due_date": string("期限 yyyy-MM-dd（記録で明言された場合のみ）"),
            "meeting_id": string("元になった会議のid（任意）")
          ], required: ["title"])
        ]
      ], required: ["tasks"])
    case .createProject:
      return object(["name": string("プロジェクト名")], required: ["name"])
    case .moveRecordsToProject:
      return object([
        "record_ids": ["type": "array", "items": ["type": "string"], "description": "会議の記録のid"],
        "project_id": string("移動先のプロジェクトid")
      ], required: ["record_ids", "project_id"])
    case .addJournalMemo:
      return object([
        "title": string("メモのタイトル"),
        "body": string("メモの本文")
      ], required: ["title", "body"])
    case .createCalendarEvent:
      return object([
        "title": string("予定の名前"),
        "start": string("開始 yyyy-MM-dd HH:mm"),
        "duration_minutes": ["type": "integer", "description": "長さ（分）。既定60"],
        "location": string("場所（任意）"),
        "notes": string("メモ（任意）")
      ], required: ["title", "start"])
    case .draftEmail:
      return object([
        "subject": string("件名"),
        "body": string("本文"),
        "to": ["type": "array", "items": ["type": "string"], "description": "宛先のメールアドレス（分かる場合のみ）"]
      ], required: ["subject", "body"])
    case .saveToNotion:
      return object(["meeting_id": string("会議の記録のid")], required: ["meeting_id"])
    case .saveMemory:
      return object(["text": string("覚える内容。短い一文（例: 営業部のマネージャー）")], required: ["text"])
    case .searchEmail:
      return object([
        "query": string("Gmailの検索語。空なら受信トレイの新しい順"),
        "limit": ["type": "integer", "description": "最大件数（1〜15、既定8）"]
      ], required: ["query"])
    case .readEmail:
      return object(["id": string("メールのid")], required: ["id"])
    case .askUser:
      return object([
        "questions": [
          "type": "array",
          "description": "質問。1〜3問",
          "items": object([
            "question": string("質問文"),
            "multiple": ["type": "boolean", "description": "複数選べるか"],
            "options": ["type": "array", "items": ["type": "string"], "description": "選択肢（2〜5個）"]
          ], required: ["question", "options"])
        ]
      ], required: ["questions"])
    }
  }

  private func object(_ properties: [String: Any], required: [String]) -> [String: Any] {
    ["type": "object", "properties": properties, "required": required]
  }

  private func string(_ description: String) -> [String: Any] {
    ["type": "string", "description": description]
  }
}
