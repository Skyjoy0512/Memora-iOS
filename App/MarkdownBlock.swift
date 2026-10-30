import Foundation

/// One block of a markdown document, as the summary view draws it.
enum MarkdownBlock: Hashable, Sendable {
  case heading(level: Int, text: String)
  case paragraph(String)
  case bullet(level: Int, marker: Marker, text: String)
  case quote(String)
  case code(language: String, text: String)
  case table(header: [String], rows: [[String]])
  case rule

  enum Marker: Hashable, Sendable {
    case dot
    case number(String)
    case checkbox(isChecked: Bool)
  }
}
