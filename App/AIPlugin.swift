import Foundation

struct AIPlugin: Identifiable {
  var id: String
  var name: String
  var summary: String
  var aliases: [String]
  var kind: Kind
  var state: Connection
  var toolIDs: Set<String>
  var permissions: [String]
  var cost: Cost
  var provider: AIToolDefinition.Provider
  var serviceID: String?
  var recordID: UUID?
  var templateID: UUID? = nil
  var iconIdentifier: String? = nil

  var icon: AIPluginIcon { AIPluginIcon.resolve(pluginID: id, name: name, iconIdentifier: iconIdentifier) }

  enum Kind: String, CaseIterable { case connected = "接続済みアプリ", builtin = "Memoraのツール", skill = "スキル", template = "会社テンプレート", file = "ファイル・記録", connectable = "接続が必要なサービス", unavailable = "現在利用できないサービス" }
  enum Connection: Equatable {
    case ready, setup(String), unavailable(String)
    var label: String {
      switch self { case .ready: "利用可能"; case .setup: "設定が必要"; case .unavailable: "利用不可" }
    }
    var reason: String? {
      switch self { case .ready: nil; case .setup(let reason), .unavailable(let reason): reason }
    }
    var isReady: Bool { self == .ready }
  }
  enum Cost: String { case local = "端末内処理", verifiedFree = "無料と確認済み", paid = "料金が発生", unknown = "料金未確認" }

  func matches(_ query: String) -> Bool {
    query.isEmpty || ([name, summary] + aliases + toolIDs.sorted()).contains { $0.localizedStandardContains(query) }
  }
}
