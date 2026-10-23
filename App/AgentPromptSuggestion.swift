import Foundation

/// Suggestions stage editable requests; source identifiers never grant tool access.
struct AgentPromptSuggestion: Identifiable, Equatable {
  enum Kind: String {
    case tasks, mail, document, priorities
  }

  var kind: Kind
  var sourceRecordID: UUID?
  var sourceTaskID: UUID?
  var sourceTitle: String?
  var id: String { kind.rawValue }

  var title: LocalizedStringResource {
    switch kind {
    case .tasks: "記録からタスク候補を作る"
    case .mail: "フォローアップメールを下書き"
    case .document: "記録を資料にまとめる"
    case .priorities: "未完了タスクの次の一歩を決める"
    }
  }

  var prompt: String {
    let subject = sourceTitle.map { "「\($0)」" } ?? "参照できる記録"
    return switch kind {
    case .tasks: "\(subject)から決定事項と次にやることを整理し、タスク候補を作って。保存する前に内容を確認させて。"
    case .mail: "\(subject)をもとにフォローアップメールを下書きして。宛先は推測せず、本文と宛先を確認させて。送信はしないで。"
    case .document: "\(subject)の要点と出典を整理して、レポートの構成を作って。資料を保存する前に内容を確認させて。"
    case .priorities: "未完了タスク\(sourceTitle.map { "「\($0)」" } ?? "")について、関連する記録と期限から次の一歩を提案して。変更する前に確認させて。"
    }
  }

  static func make(recordID: UUID? = nil, recordTitle: String? = nil,
                   taskID: UUID? = nil, taskTitle: String? = nil) -> [Self] {
    let recordTitle = recordID == nil ? nil : boundedTitle(recordTitle)
    let taskTitle = taskID == nil ? nil : boundedTitle(taskTitle)
    let recordID = recordTitle == nil ? nil : recordID
    let taskID = taskTitle == nil ? nil : taskID
    return [
      taskID.map { Self(kind: .priorities, sourceTaskID: $0, sourceTitle: taskTitle) }
        ?? Self(kind: .tasks, sourceRecordID: recordID, sourceTitle: recordTitle),
      Self(kind: .mail, sourceRecordID: recordID, sourceTitle: recordTitle),
      Self(kind: .document, sourceRecordID: recordID, sourceTitle: recordTitle)
    ]
  }

  private static func boundedTitle(_ title: String?) -> String? {
    guard let title else { return nil }
    let value = title.prefix(100).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    return value.isEmpty ? nil : value
  }
}
