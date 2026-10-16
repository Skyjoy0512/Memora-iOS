import Foundation

struct ArtifactSourceRow: Identifiable {
  var target: ArtifactSourceTarget
  var title: String
  var hasChanged: Bool?
  var allowsCloudAI: Bool
  var canOpen: Bool
  var id: ArtifactSourceTarget { target }

  var status: String {
    guard canOpen else { return "元の情報が見つかりません" }
    let change = hasChanged.map { $0 ? "参照後に変更あり" : "参照後の変更なし" } ?? "生成時点の内容は未記録"
    return allowsCloudAI ? change : change + "・外部AIへの送信不可"
  }
}
