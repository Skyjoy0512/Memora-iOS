import Foundation

/// The tools the Ask AI agent may call. Reading tools run straight away; a tool
/// that changes something waits for the person's approval first.
enum AgentTool: String, CaseIterable {
  case searchRecords = "search_records"
  case readRecord = "read_record"
  case listProjects = "list_projects"
  case listTasks = "list_tasks"
  case createDocument = "create_document"
  case createSlides = "create_slides"
  case addTasks = "add_tasks"
  case createProject = "create_project"
  case moveRecordsToProject = "move_records_to_project"
  case addJournalMemo = "add_journal_memo"

  /// True for tools that change the person's data.
  var needsApproval: Bool {
    switch self {
    case .searchRecords, .readRecord, .listProjects, .listTasks: false
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
    case .createDocument: .docRichtext
    case .createSlides: .rectangleOnRectangleAngled
    case .createProject: .folderBadgePlus
    case .addJournalMemo: .squareAndPencil
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
    }
  }

  private func object(_ properties: [String: Any], required: [String]) -> [String: Any] {
    ["type": "object", "properties": properties, "required": required]
  }

  private func string(_ description: String) -> [String: Any] {
    ["type": "string", "description": description]
  }
}
