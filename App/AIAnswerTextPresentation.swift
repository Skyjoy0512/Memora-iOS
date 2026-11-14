import Foundation

/// Present the selected answer atomically, including on the first sheet opening.
struct AIAnswerTextPresentation: Identifiable {
  let id = UUID()
  var text: String
}
