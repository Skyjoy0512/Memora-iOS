import Foundation

/// Explicit statements and approved suggestions; never inferred from ordinary chat.
struct AIMemory: Identifiable, Hashable, Codable {
  enum Origin: String, Codable { case told, agent }
  enum Status: String, Codable, CaseIterable {
    case current, updateCandidate, historical, conflicted, unconfirmed, disabled
    var label: String {
      switch self {
      case .current: "現在有効"
      case .updateCandidate: "更新候補"
      case .historical: "過去の情報"
      case .conflicted: "矛盾あり"
      case .unconfirmed: "未確認"
      case .disabled: "無効化"
      }
    }
  }
  enum Kind: String, Codable, CaseIterable {
    case fact, style, role, constraint, project
    var label: String {
      switch self { case .fact: "事実・メモ"; case .style: "文章の好み"; case .role: "役割"; case .constraint: "作業上の制約"; case .project: "継続中のプロジェクト" }
    }
  }
  enum Sensitivity: String, Codable, CaseIterable {
    case standard, sensitive
    var label: String { self == .standard ? "通常" : "機微情報（AIへ自動送信しない）" }
  }
  struct Semantic: Hashable, Codable {
    var type: Kind = .fact
    var subjectID = "user"
    var predicate = "note"
    var value: String
    var sourceReference: String
    var observedAt: Date
    var updatedAt: Date
    var validFrom: Date
    var validTo: Date?
    var status: Status = .current
    var confidence = 1.0
    var workspaceID: String?
    var sensitivity: Sensitivity = .standard
    var userConfirmed = true
  }
  struct Revision: Hashable, Codable {
    var text: String
    var semantic: Semantic?
    var supersededAt: Date
  }

  var id: UUID
  var text: String
  var origin: Origin
  var createdAt: Date
  var semantic: Semantic?
  var revisions: [Revision]?

  var status: Status { semantic?.status ?? .current }
  var updatedAt: Date { semantic?.updatedAt ?? createdAt }
  var workspaceID: String? { semantic?.workspaceID }

  func canUse(workspaceID: String?, now: Date = .now) -> Bool {
    self.workspaceID == workspaceID && status == .current
      && (semantic?.userConfirmed ?? true) && (semantic?.sensitivity ?? .standard) == .standard
      && (semantic?.validFrom ?? createdAt) <= now && (semantic?.validTo.map { now < $0 } ?? true)
  }
}
