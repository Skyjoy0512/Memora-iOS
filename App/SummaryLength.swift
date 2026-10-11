import Foundation

enum SummaryLength: String, Codable, CaseIterable, Identifiable {
  case concise, standard, detailed
  var id: Self { self }
  var title: String {
    switch self {
    case .concise: "簡潔"
    case .standard: "標準"
    case .detailed: "詳細"
    }
  }
  var instruction: String {
    switch self {
    case .concise: "各見出しは重要な事実を1〜3項目に絞る。詳細な経緯は省くが、注意点・約束・未確認事項は落とさない。"
    case .standard: "各見出しで重要な事実と必要な背景を簡潔に整理する。"
    case .detailed: "根拠のある具体例・経緯・理由も含めて詳しく整理する。文字起こしにない情報で長さを増やさない。"
    }
  }
}
