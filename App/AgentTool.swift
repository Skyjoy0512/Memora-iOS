import Foundation

/// The tools the Ask AI agent may call. Reading tools run straight away; a tool
/// that changes something waits for the person's approval first.
enum AgentTool: String, CaseIterable {
  case searchRecords = "search_records"
  case readRecord = "read_record"
  case listProjects = "list_projects"
  case listTasks = "list_tasks"
  case reviewPeriod = "review_period"
  case updateTasks = "update_tasks"
  case readPerson = "read_person"
  case createDocument = "create_document"
  case createSlides = "create_slides"
  case addTasks = "add_tasks"
  case createProject = "create_project"
  case moveRecordsToProject = "move_records_to_project"
  case addJournalMemo = "add_journal_memo"
  case readCalendar = "read_calendar"
  case createCalendarEvent = "create_calendar_event"
  case draftEmail = "draft_email"
  case saveToNotion = "save_to_notion"
  case saveMemory = "save_memory"
  case searchEmail = "search_email"
  case readEmail = "read_email"
  case askUser = "ask_user"
  case delegateResearch = "delegate_research"
  case searchWeb = "search_web"
  case deepResearch = "deep_research"

  /// The tools offered right now: mail only while Gmail is connected, so the
  /// model is never handed a tool that cannot work.
  @MainActor
  static var offered: [AgentTool] {
    allCases.filter { (!$0.needsGmail || (GmailService.shared.isConnected && GmailService.isConfigured)) && (!($0 == .searchWeb || $0 == .deepResearch) || KeychainStore.has(WebResearchClient.keyName)) }
  }

  @MainActor
  static var offeredOnDevice: [AgentTool] {
    onDeviceTools.filter { (!$0.needsGmail || (GmailService.shared.isConnected && GmailService.isConfigured)) && (!($0 == .searchWeb || $0 == .deepResearch) || KeychainStore.has(WebResearchClient.keyName)) }
  }

  /// What a resident agent may use while it works unattended: reading only,
  /// and no questions, since nobody may be there to answer.
  @MainActor
  static var residentTools: [AgentTool] {
    offered.filter { !$0.needsApproval && $0 != .askUser && $0 != .delegateResearch && $0 != .readCalendar }
  }

  var needsGmail: Bool {
    self == .searchEmail || self == .readEmail
  }

  /// The tools offered to the on-device model. Its context is small, so the
  /// long-form writers (slides) and the rarer organising tools stay with the
  /// cloud models.
  static let onDeviceTools: [AgentTool] = [
    .searchRecords, .readRecord, .readPerson, .listTasks, .reviewPeriod, .readCalendar, .addTasks, .createDocument,
    .createProject, .addJournalMemo, .createCalendarEvent, .draftEmail, .searchEmail, .readEmail, .searchWeb, .deepResearch
  ]

  /// True for tools that change the person's data.
  var needsApproval: Bool {
    switch self {
    case .searchRecords, .readRecord, .readPerson, .listProjects, .listTasks, .reviewPeriod, .searchEmail, .readEmail, .readCalendar, .askUser: false
    default: true
    }
  }

  /// The icon a step or approval card for this tool is drawn with.
  var icon: MemoraIcon {
    switch self {
    case .searchRecords: .magnifyingglass
    case .readRecord: .docText
    case .listProjects, .moveRecordsToProject: .folder
    case .listTasks, .addTasks, .updateTasks: .checklist
    case .reviewPeriod, .readCalendar: .calendar
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
    case .searchWeb, .deepResearch: .magnifyingglass
    case .delegateResearch: .sparkle
    }
  }

  var summary: String {
    switch self {
    case .searchWeb: "利用者の承認後、BraveでWeb検索する。検索抜粋と出典URLを返し、調査履歴に保存する。端末の非公開情報を検索語へ勝手に入れない。追加料金が発生する。1依頼1回。"
    case .deepResearch: "利用者の承認後、最大3つの具体的な検索語でWeb抽出本文を取得する。queryに調査テーマ、queriesに重複しない検索語を1〜3件指定。取得した根拠だけ比較する。全文読了や網羅性を保証しない。1依頼1回。"
    case .delegateResearch:
      "複雑な依頼の調査を2〜3担当に分け、承認後に並列実行する。担当ごとの役割と具体的な調査依頼を指定する。子担当は読み取りのみ。結果を統合してから、必要な変更を通常の承認付き道具で行う。1依頼につき1回。追加API利用あり。"
    case .searchRecords:
      "会議の記録とジャーナルをキーワードで検索し、id・タイトル・日付・概要を返す。空のqueryなら新しい順。"
    case .readRecord:
      "search_recordsで得たidの記録を読む。会議なら要約・決定事項・タスク・文字起こしを返す。"
    case .listProjects:
      "プロジェクトの一覧（id・名前・記録の数）を返す。"
    case .listTasks:
      "タスクの一覧（タイトル・担当・期限・元の会議）を返す。"
    case .reviewPeriod:
      "期間内の会議件数・録音時間・完了タスク・メモ・写真を全件集計する。週や月の振り返り、件数・時間の質問には検索結果を数えずこの道具を使う。健康・位置情報は含まない。"
    case .updateTasks:
      "指定したタスクの取り組む日・進み具合・完了状態をまとめて変更する。変更前後を表示して承認を待つ。期限・担当・本文は変更しない。"
    case .readPerson:
      "人物に関連する会議・人物を指定した担当タスク・名前のみ一致する未確認タスクを返す。担当の指定は発言や約束の確定ではない。会議全体の決定と本人の合意を区別する。確認済みperson_idを優先し、その場合nameは空文字でもよい。両方が空なら人物候補の一覧。"
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
    case .readCalendar:
      "端末のカレンダーで指定日 yyyy-MM-dd の予定を取得する。Google接続とは別で、許可がない場合は設定を案内する。"
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
    case .searchWeb, .deepResearch:
      return object([
        "query": string("Webへ送る調査テーマ。600文字・75語以内"),
        "queries": ["type": "array", "maxItems": 3, "items": string("Webへ送る検索語。600文字以内")]
      ], required: self == .deepResearch ? ["query", "queries"] : ["query"])
    case .delegateResearch:
      return object([
        "assignments": ["type": "array", "minItems": 2, "maxItems": 3,
          "items": object([
            "role": string("担当名・役割（例: 会議整理、タスク確認、ジャーナル分析）"),
            "request": string("この担当だけが調べる具体的な依頼。期間・対象・必要な根拠を含める")
          ], required: ["role", "request"])]
      ], required: ["assignments"])
    case .searchRecords:
      return object([
        "query": string("検索語。空白区切りで複数可"),
        "limit": ["type": "integer", "description": "最大件数（1〜20、既定8）"]
      ], required: ["query"])
    case .readRecord:
      return object(["id": string("記録のid")], required: ["id"])
    case .readCalendar:
      return object(["date": string("指定日 yyyy-MM-dd（端末のタイムゾーン）")], required: ["date"])
    case .listProjects:
      return object([:], required: [])
    case .listTasks:
      return object([
        "include_completed": ["type": "boolean", "description": "完了済みも含めるか"]
      ], required: [])
    case .reviewPeriod:
      return object([
        "start_date": string("開始日 yyyy-MM-dd（端末のタイムゾーン）"),
        "end_date": string("終了日 yyyy-MM-dd。この日を含む。最大366日")
      ], required: ["start_date", "end_date"])
    case .updateTasks:
      var update = object([
          "id": string("list_tasksで得たタスクid"),
          "work_date": string("取り組む日 yyyy-MM-dd。空文字で解除。省略で維持"),
          "progress": string("notStarted / inProgress / waiting。省略で維持"),
          "is_completed": ["type": "boolean", "description": "完了状態。省略で維持"]
        ], required: ["id"])
      update["additionalProperties"] = false
      var schema = object([
        "updates": ["type": "array", "minItems": 1, "maxItems": 30, "items": update]
      ], required: ["updates"])
      schema["additionalProperties"] = false
      return schema
    case .readPerson:
      return object(["name": string("人の名前。曖昧なら候補を確認する。確認済みperson_idがあれば空文字でもよい。両方が空なら候補一覧"), "person_id": string("確認済みの人物UUID。名前より優先")], required: ["name"])
    case .createDocument:
      return object([
        "title": string("資料のタイトル"),
        "markdown": string("本文（Markdown）。タイトルの見出しは含めない"),
        "project_id": string("入れるプロジェクトのid（任意）"),
        "template_id": string("利用者が選択した会社テンプレートのid（任意）"),
        "template_fields": ["type": "array", "maxItems": 30, "items": object([
          "name": string("差し込み項目名"), "value": string("差し込む文字列。PPTXは120文字以内")
        ], required: ["name", "value"])]
      ], required: ["title", "markdown"])
    case .createSlides:
      return object([
        "title": string("スライド資料のタイトル"),
        "plan_json": string("型を選ぶ前に作る資料計画のJSON。purpose:目的、audience:対象読者、decision:判断してほしいこと、assumptions:[未確認の前提]、storyline:[{slide_number:1始まり,claim:そのページの主張,evidence:[確認した出典と箇所],unconfirmed:[未確認事項]}]。不明な対象読者等は空文字とassumptionsで未確認を明示。タイトルに型名を使わない。最大50KB。"),
        "slides": [
          "type": "array",
          "maxItems": 65,
          "description": "先に根拠付きの主張の列を作り、各主張に合うlayoutを選ぶ。構造化レイアウトはcontent_jsonに実データを渡す。必要データがない型は選ばない。",
          "items": object([
            "title": string("スライドの見出し"),
            "layout": ["type": "string", "enum": (1...30).map { String(format: "b%02d", $0) } + (1...35).map { String(format: "m%02d", $0) }, "description": "65型。未指定なら従来の箇条書き。PowerPointスキルの型対応に従う"],
            "content_json": string("layout指定時は必須のJSON object。items:[{heading,body}]、table:{columns:[文字列],rows:[[文字列]],scores:[[0〜1]],rowGroups:[文字列]}、metrics:[{label,value:数値,unit,detail}]、chart:{kind:bar/line/pie/stacked/scatter/waterfall,categories:[文字列],series:[{name,values:[数値]}],xLabel,yLabel,unit,points:[{label,x,y}],totalIndices:[0始まりの絶対値バー位置]}、diagram:{nodes:[{id,label,level:0〜3}],edges:[{from,to,label}]}、schedule:{periods:[文字列],entries:[{label,lane,start:0始まり,end:含む}]}。共通:subtitle,annotations:[文字列],sources:[{title,locator,excerpt}]。必要な項目だけ。出典と数値は許可された原資料から。項目最大6、表6×6、グラフ4系列10区分。図形位置はアプリが決める。"),
            "bullets": ["type": "array", "items": ["type": "string"], "description": "要点"],
            "notes": string("発表時の補足と、確認した記録の資料名・参照箇所（任意）。PowerPointの発表者ノートへ出力。未確認の出典を作らない")
          ], required: ["title", "bullets"])
        ],
        "project_id": string("入れるプロジェクトのid（任意）"),
        "template_id": string("利用者が選択した会社テンプレートのid（任意）"),
        "template_fields": ["type": "array", "maxItems": 30, "items": object([
          "name": string("差し込み項目名"), "value": string("差し込む文字列。PPTXは120文字以内")
        ], required: ["name", "value"])]
      ], required: ["title", "slides"])
    case .addTasks:
      return object([
        "tasks": [
          "type": "array",
          "minItems": 1,
          "maxItems": 30,
          "items": object([
            "title": string("タスクの内容"),
            "detail": string("根拠や詳細。資料に記載された内容のみ（任意、4,000字以内）"),
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
        "to": ["type": "array", "items": ["type": "string"], "description": "確認済みの宛先。不明なら空配列。推測しない"],
        "cc": ["type": "array", "items": ["type": "string"]],
        "bcc": ["type": "array", "items": ["type": "string"]]
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

extension AgentToolCall {
  var tool: AgentTool? { AgentTool(rawValue: name) }
}
