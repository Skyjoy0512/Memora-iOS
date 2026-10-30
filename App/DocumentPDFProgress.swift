import Foundation

enum DocumentPDFProgress: Equatable, Sendable {
  case preparing
  case writing(completed: Int, total: Int)
}
