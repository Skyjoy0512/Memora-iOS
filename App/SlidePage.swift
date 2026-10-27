import Foundation

/// Presentation pages are derived, so pagination never rewrites saved slides.
struct SlidePage: Identifiable, Equatable {
  var sourceID: UUID
  var fragment: Int
  var titleLines: [String]
  var bullets: [Bullet]
  var notes: String
  var isCover: Bool
  var elements: [PresentationElement]? = nil
  var readingText: [String]? = nil

  var id: String { "\(sourceID.uuidString):\(fragment)" }
  var title: String { titleLines.joined() }

  struct Bullet: Identifiable, Equatable {
    var sourceIndex: Int
    var firstLine: Int
    var lines: [String]

    var id: String { "\(sourceIndex):\(firstLine)" }
    var text: String { lines.joined() }
    var showsMarker: Bool { firstLine == 0 }
  }
}
