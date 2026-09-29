import Foundation

/// What a document is laid out as. Raw values are stored, so they never change.
enum MemoraDocumentKind: String, Codable, CaseIterable, Identifiable, Sendable {
  case document
  case slides

  var id: Self { self }

  var label: String {
    switch self {
    case .document: "資料"
    case .slides: "スライド"
    }
  }

  var symbol: MemoraIcon {
    switch self {
    case .document: .docRichtext
    case .slides: .rectangleOnRectangleAngled
    }
  }
}
