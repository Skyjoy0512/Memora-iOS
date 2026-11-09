import Foundation

struct NativeAIInterface: Codable, Equatable {
  var version: Int
  var components: [Component]

  enum Kind: String, Codable, CaseIterable {
    case taskList = "TaskList", documentCard = "DocumentCard", projectCard = "ProjectCard"
    case sourceList = "SourceList", comparisonTable = "ComparisonTable"
    case timeline = "Timeline", chart = "Chart", actionBar = "ActionBar"
    case taskProgress = "TaskProgress", mailDraftCard = "MailDraftCard", disclosure = "Disclosure"
    case calendarPreview = "CalendarPreview"
    /// Read-only layout of other components, so two answers can sit side by side
    /// or stacked. A container holds no items of its own and its children cannot
    /// nest further, so an answer stays one shallow layout, not a free tree.
    case row = "Row", column = "Column"
  }

  struct Component: Codable, Equatable, Identifiable {
    var id: String
    var kind: Kind
    var title: String?
    var columns: [String]?
    var items: [Item]
    /// The children of a Row/Column. nil for every other kind.
    var components: [Component]?

    init(id: String, kind: Kind, title: String? = nil, columns: [String]? = nil,
         items: [Item] = [], components: [Component]? = nil) {
      self.id = id
      self.kind = kind
      self.title = title
      self.columns = columns
      self.items = items
      self.components = components
    }

    private enum CodingKeys: String, CodingKey { case id, kind, title, columns, items, components }

    /// `items` is decoded leniently so a Row/Column, which carries `components`
    /// instead, does not have to send an empty `items` array.
    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      id = try container.decode(String.self, forKey: .id)
      kind = try container.decode(Kind.self, forKey: .kind)
      title = try container.decodeIfPresent(String.self, forKey: .title)
      columns = try container.decodeIfPresent([String].self, forKey: .columns)
      items = try container.decodeIfPresent([Item].self, forKey: .items) ?? []
      components = try container.decodeIfPresent([Component].self, forKey: .components)
    }
  }

  struct Item: Codable, Equatable, Identifiable {
    var id: String
    var title: String?
    var detail: String?
    var referenceID: UUID?
    var cells: [String]?
    var value: Double?
    var action: Action?
  }

  enum Action: String, Codable { case completeTask }

  static func decode(_ json: String) -> Self? {
    guard json.utf8.count <= 32 * 1024, let data = json.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data),
          ToolInputValidator.accepts(object, schema: schema),
          let ui = try? JSONDecoder().decode(Self.self, from: data),
          Set(ui.components.map(\.id)).count == ui.components.count else { return nil }
    for component in ui.components where !isValid(component, isNested: false) { return nil }
    return ui
  }

  /// A component, and for a Row/Column its read-only children. Every kind is
  /// bounded here rather than in the schema, because a container has no items
  /// while every other kind must have some.
  private static func isValid(_ component: Component, isNested: Bool) -> Bool {
    guard Set(component.items.map(\.id)).count == component.items.count else { return false }
    switch component.kind {
    case .row, .column:
      guard !isNested, let children = component.components, (1...4).contains(children.count),
            component.items.isEmpty, component.columns == nil, component.title == nil else { return false }
      for child in children {
        guard child.kind != .row, child.kind != .column, isValid(child, isNested: true) else { return false }
      }
      return true
    case .taskList, .documentCard, .projectCard, .sourceList, .actionBar, .taskProgress, .mailDraftCard, .calendarPreview:
      guard component.components == nil, (1...30).contains(component.items.count) else { return false }
      for item in component.items {
        guard item.referenceID != nil, item.cells == nil, item.value == nil else { return false }
        switch component.kind {
        case .actionBar:
          guard item.action == .completeTask else { return false }
        case .calendarPreview:
          guard item.title == nil, item.detail == nil, item.action == nil else { return false }
        case .taskList:
          guard item.action == nil || item.action == .completeTask else { return false }
        default:
          guard item.action == nil else { return false }
        }
      }
    case .comparisonTable:
      guard component.components == nil, (1...30).contains(component.items.count),
            let columns = component.columns, (2...6).contains(columns.count) else { return false }
      for item in component.items {
        guard item.cells?.count == columns.count, item.action == nil, item.value == nil else { return false }
      }
    case .chart:
      guard component.components == nil, (1...30).contains(component.items.count) else { return false }
      for item in component.items {
        guard let value = item.value, value.isFinite, item.title?.isEmpty == false,
              item.action == nil, item.referenceID == nil, item.cells == nil else { return false }
      }
    case .timeline, .disclosure:
      guard component.components == nil, (1...30).contains(component.items.count) else { return false }
      for item in component.items {
        guard item.title?.isEmpty == false, item.action == nil, item.referenceID == nil,
              item.value == nil, item.cells == nil else { return false }
      }
    }
    if component.kind != .comparisonTable, component.columns != nil { return false }
    if component.kind == .disclosure, component.title?.isEmpty != false { return false }
    if component.kind == .taskProgress || component.kind == .mailDraftCard || component.kind == .calendarPreview,
       Set(component.items.compactMap(\.referenceID)).count != component.items.count { return false }
    return true
  }

  /// One optional interface follows a complete Markdown answer. The text is
  /// still useful when the interface is invalid or the history is read elsewhere.
  static func response(_ text: String, isStreaming: Bool = false) -> (markdown: String, interface: Self?) {
    var stream = NativeAIComponentStream()
    return response(text, isStreaming: isStreaming, stream: &stream)
  }

  static func response(_ text: String, isStreaming: Bool, stream: inout NativeAIComponentStream) -> (markdown: String, interface: Self?) {
    let marker = "```memora-ui"
    guard let start = text.range(of: marker) else {
      if isStreaming {
        let start = text.lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        let line = text[start...].trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("```"), marker.hasPrefix(line) {
          return (String(text[..<start]).trimmingCharacters(in: .whitespacesAndNewlines), nil)
        }
      }
      return (text, nil)
    }
    let markdown = String(text[..<start.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    let suffix = text[start.upperBound...]
    let fallback = markdown.isEmpty && !isStreaming ? "構造化表示を読み込めませんでした。もう一度回答を依頼してください。" : markdown
    if isStreaming {
      if let end = suffix.range(of: "```") {
        guard suffix[end.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return (fallback, nil) }
        return (markdown, stream.update(String(suffix[..<end.lowerBound])))
      }
      return (markdown, stream.update(String(suffix)))
    }
    guard let end = suffix.range(of: "```"), suffix[end.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return (fallback, nil) }
    guard let interface = decode(String(suffix[..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)) else { return (fallback, nil) }
    return (markdown, interface)
  }

  /// Reference-backed cards use the same live grants as their onscreen views.
  /// Display JSON never supplies replacement titles, event dates or task counts.
  static func exportMarkdown(_ text: String,
    referenceText: (Kind, [UUID]) -> [String]? = { _, _ in nil }
  ) -> String {
    let response = response(text)
    guard let interface = response.interface else { return response.markdown }
    func cell(_ text: String) -> String {
      text.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "|", with: "\\|")
        .components(separatedBy: .newlines).joined(separator: " ")
    }
    func block(_ component: Component) -> String {
      if component.kind == .row || component.kind == .column {
        return (component.components ?? []).map(block).filter { !$0.isEmpty }.joined(separator: "\n\n")
      }
      var lines: [String] = []
      if let title = component.title, !title.isEmpty {
        lines.append("### " + title.components(separatedBy: .newlines).joined(separator: " "))
      }
      switch component.kind {
      case .comparisonTable:
        let columns = component.columns ?? []
        lines.append("| " + columns.map(cell).joined(separator: " | ") + " |")
        lines.append("| " + columns.map { _ in "---" }.joined(separator: " | ") + " |")
        lines += component.items.map { "| " + ($0.cells ?? []).map(cell).joined(separator: " | ") + " |" }
      case .chart:
        lines += component.items.map { "- \($0.title ?? ""): \(($0.value ?? 0).formatted())" }
      case .timeline, .disclosure:
        lines += component.items.map { item in
          "- " + (item.title ?? "") + (item.detail.map { "\n  " + $0.replacingOccurrences(of: "\n", with: "\n  ") } ?? "")
        }
      case .row, .column: break
      default:
        if let resolved = referenceText(component.kind, component.items.compactMap(\.referenceID)) {
          lines += resolved.map { "- " + $0 }
        } else {
          lines.append("この項目は現在参照できません。")
        }
      }
      return lines.joined(separator: "\n")
    }
    return ([response.markdown] + interface.components.map(block))
      .filter { !$0.isEmpty }.joined(separator: "\n\n")
  }

  static var instructions: String {
    """
    通常はMarkdownだけで答える。操作・比較・日程の表示が明確に役立つ場合だけ、完全なMarkdown回答の末尾に1つの```memora-ui JSONブロックを付けてよい。
    形式: {"version":1,"components":[{"id":"unique","kind":"TaskList","title":"今週のタスク","items":[{"id":"unique-item","referenceID":"list_tasksで実際に得たUUID","action":"completeTask"}]}]}。
    kindはTaskList/DocumentCard/ProjectCard/SourceList/ComparisonTable/Timeline/Chart/ActionBar/TaskProgress/MailDraftCard/Disclosure/CalendarPreviewだけ。最大8部品・各30項目。URL・コード・任意のツール名は渡さない。
    Row/Columnは2つ以上の既存部品を横または縦に並べるためだけに使い、itemsではなくcomponentsに子部品を入れる。入れ子は1段まで（Row/Columnの中にRow/Columnは置かない）。装飾や余白の調整には使わない。
    CalendarPreviewはread_calendarが返したreferenceIDだけをitemsに並べる。各itemのtitle/detail/value/actionは指定しない。実際の予定名と日時をアプリが表示する。未取得の予定、空の検索結果、失効した予定を作って補わない。
    TaskProgressはlist_tasksで実際に得たタスクのreferenceIDを重複なく並べる。進捗の数値はアプリが現在のタスクから計算するのでvalueは指定しない。MailDraftCardはこの回答のdraft_emailで保存された下書きIDだけをreferenceIDにする。Disclosureは短いtitleを必須とし、各itemsのtitle/detailを折りたためる補足に使う。操作や進捗の捏造には使わない。
    参照型は実際に読んだUUIDだけ。ComparisonTableはcolumnsと各項目cells（同じ列数）、Timelineはtitle/detail、Chartはtitle/valueを使う。ComparisonTableの各項目は、その行の根拠になった記録が実際にある場合だけreferenceIDを付け、無ければ付けない。数字は実際のツール結果に基づき単位をtitleに示す。取得していない統計を作らない。承認・質問・進行状態はアプリの実際のカードに任せる。UIがなくても意味の通る回答を先に書く。
    """
  }

  static var schema: [String: Any] {
    let short: [String: Any] = ["type": "string", "maxLength": 120]
    let identifier: [String: Any] = ["type": "string", "minLength": 1, "maxLength": 80]
    let item: [String: Any] = ["type": "object", "additionalProperties": false, "required": ["id"], "properties": [
      "id": identifier, "title": short, "detail": ["type": "string", "maxLength": 2_000], "referenceID": identifier,
      "cells": ["type": "array", "maxItems": 6, "items": ["type": "string", "maxLength": 500]],
      "value": ["type": "number", "minimum": 0, "maximum": 1_000_000_000_000],
      "action": ["type": "string", "enum": ["completeTask"]]
    ]]
    // A leaf has no children, so a Row/Column cannot nest another one. `items`
    // and `components` are both optional in the schema; which one a kind must
    // have is decided in `isValid`.
    let leaf: [String: Any] = ["type": "object", "additionalProperties": false, "required": ["id", "kind"], "properties": [
      "id": identifier, "kind": ["type": "string", "enum": Kind.allCases.map(\.rawValue)], "title": short,
      "columns": ["type": "array", "minItems": 2, "maxItems": 6, "items": short],
      "items": ["type": "array", "maxItems": 30, "items": item]
    ]]
    var component = leaf
    var properties = leaf["properties"] as! [String: Any]
    properties["components"] = ["type": "array", "minItems": 1, "maxItems": 4, "items": leaf]
    component["properties"] = properties
    return ["type": "object", "additionalProperties": false, "required": ["version", "components"], "properties": [
      "version": ["type": "integer", "enum": [1]],
      "components": ["type": "array", "minItems": 1, "maxItems": 8, "items": component]
    ]]
  }
}
