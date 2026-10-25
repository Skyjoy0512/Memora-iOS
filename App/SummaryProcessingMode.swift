import Foundation

/// Processing policy, independent of how detailed the finished document is.
enum SummaryProcessingMode: String, Codable, CaseIterable, Sendable {
  case fast, balanced, accurate

  var diagnosticCode: Int {
    switch self {
    case .fast: 0
    case .balanced: 1
    case .accurate: 2
    }
  }

  var title: String {
    switch self {
    case .fast: "高速"
    case .balanced: "標準"
    case .accurate: "高精度"
    }
  }

  var detail: String {
    switch self {
    case .fast: "対応するDeepSeekでは推論を無効にし、長文の区間整理を最大2件同時に実行します。重要事項と出典は省略しません。"
    case .balanced: "従来の生成設定で、長文は順番に整理します。要約の詳しさとは別の設定です。"
    case .accurate: "対応するDeepSeekでは推論を有効にします。処理に時間がかかる場合があります。正確性を保証するものではありません。"
    }
  }
}
