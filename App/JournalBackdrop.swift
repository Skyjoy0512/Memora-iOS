import Foundation

enum JournalBackdrop: String, CaseIterable {
  case forest, lake, leaves, sunset

  var assetName: String { "journal-\(rawValue)" }

  var label: String {
    switch self {
    case .forest: "森"
    case .lake: "湖"
    case .leaves: "緑の葉"
    case .sunset: "夕景"
    }
  }

  static func random(excluding previous: JournalBackdrop? = nil) -> JournalBackdrop {
    allCases.filter { $0 != previous }.randomElement() ?? .forest
  }
}
