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
  }

  struct Component: Codable, Equatable, Identifiable {
    var id: String
    var kind: Kind
    var title: String?
    var columns: [String]?
    var items: [Item]
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
    for component in ui.components {
      guard Set(component.items.map(\.id)).count == component.items.count else { return nil }
      for item in component.items {
        switch component.kind {
        case .taskList, .documentCard, .projectCard, .sourceList, .actionBar, .taskProgress, .mailDraftCard, .calendarPreview:
          guard item.referenceID != nil, item.cells == nil, item.value == nil else { return nil }
          if component.kind == .actionBar, item.action != .completeTask { return nil }
          if component.kind == .calendarPreview, item.title != nil || item.detail != nil { return nil }
        case .comparisonTable:
          // A row may name the record it compares, but only a real, currently
          // permitted one becomes a link; the cell text stands on its own.
          guard let columns = component.columns, (2...6).contains(columns.count),
                item.cells?.count == columns.count, item.action == nil, item.value == nil else { return nil }
        case .chart:
          guard let value = item.value, value.isFinite, item.title?.isEmpty == false,
                item.action == nil, item.referenceID == nil, item.cells == nil else { return nil }
        case .timeline, .disclosure:
          guard item.title?.isEmpty == false, item.action == nil, item.referenceID == nil, item.value == nil, item.cells == nil else { return nil }
        }
        if item.action != nil, component.kind != .taskList && component.kind != .actionBar { return nil }
      }
      if component.kind != .comparisonTable, component.columns != nil { return nil }
      if component.kind == .disclosure, component.title?.isEmpty != false { return nil }
      if component.kind == .taskProgress || component.kind == .mailDraftCard || component.kind == .calendarPreview,
         Set(component.items.compactMap(\.referenceID)).count != component.items.count { return nil }
    }
    return ui
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

  static var instructions: String {
    """
    通常はMarkdownだけで答える。操作・比較・日程の表示が明確に役立つ場合だけ、完全なMarkdown回答の末尾に1つの```memora-ui JSONブロックを付けてよい。
    形式: {"version":1,"components":[{"id":"unique","kind":"TaskList","title":"今週のタスク","items":[{"id":"unique-item","referenceID":"list_tasksで実際に得たUUID","action":"completeTask"}]}]}。
    kindはTaskList/DocumentCard/ProjectCard/SourceList/ComparisonTable/Timeline/Chart/ActionBar/TaskProgress/MailDraftCard/Disclosure/CalendarPreviewだけ。最大8部品・各30項目。URL・コード・任意のツール名は渡さない。
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
    let component: [String: Any] = ["type": "object", "additionalProperties": false, "required": ["id", "kind", "items"], "properties": [
      "id": identifier, "kind": ["type": "string", "enum": Kind.allCases.map(\.rawValue)], "title": short,
      "columns": ["type": "array", "minItems": 2, "maxItems": 6, "items": short],
      "items": ["type": "array", "minItems": 1, "maxItems": 30, "items": item]
    ]]
    return ["type": "object", "additionalProperties": false, "required": ["version", "components"], "properties": [
      "version": ["type": "integer", "enum": [1]],
      "components": ["type": "array", "minItems": 1, "maxItems": 8, "items": component]
    ]]
  }
}
