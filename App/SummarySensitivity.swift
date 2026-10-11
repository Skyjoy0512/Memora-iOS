import Foundation

enum SummarySensitivity: String, Codable {
  case general, personal, sensitive
  var notice: String? {
    switch self {
    case .general: nil
    case .personal: "顧客・人物の情報は必要な範囲だけ記録し、録音・共有の同意を確認してください。"
    case .sensitive: "要配慮情報を含む可能性があります。人による確認が必要です。診療記録への適合性や法的証拠としての効力は保証しません。"
    }
  }
}
