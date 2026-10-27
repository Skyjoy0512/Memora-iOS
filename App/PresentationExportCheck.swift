import Foundation

enum PresentationExportCheck {
  struct Failure: LocalizedError {
    var message: String
    var errorDescription: String? { message }
  }

  static func validate(_ document: MemoraDocument) throws {
    let errors = PresentationValidator.issues(for: document).filter(\.isError)
    guard errors.isEmpty else { throw Failure(message: errors.prefix(3).map(\.message).joined(separator: "\n")) }
  }
}
