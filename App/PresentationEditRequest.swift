import Foundation

// A single sheet value keeps the document snapshot and its initial route together.
struct PresentationEditRequest: Identifiable {
  var id = UUID()
  var document: MemoraDocument
  var initialSlideID: UUID? = nil
}
