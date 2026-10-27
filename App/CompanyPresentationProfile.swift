import Foundation

/// Measurements, not a rendering promise. Part identities keep inheritance unambiguous.
struct CompanyPresentationProfile: Codable, Hashable {
  var presentationPart: String
  var widthEMU: Int
  var heightEMU: Int
  var slideCount: Int
  var masters: [Master]
  var layouts: [Layout]
  var notices: [String]

  var isValid: Bool {
    let masterIDs = Set(masters.map(\.id)), layoutIDs = Set(layouts.map(\.id))
    func bounded(_ value: String) -> Bool { !value.isEmpty && value.utf8.count <= 1024 }
    func validFrame(_ frame: Frame?) -> Bool {
      guard let frame else { return true }
      return abs(Double(frame.x)) <= 1_000_000_000 && abs(Double(frame.y)) <= 1_000_000_000 &&
        (1...1_000_000_000).contains(frame.width) && (1...1_000_000_000).contains(frame.height)
    }
    func placeholders(_ values: [Placeholder], sources: Set<String>) -> Bool {
      values.count <= 100 && Set(values.map(\.id)).count == values.count && values.allSatisfy {
        bounded($0.index) && bounded($0.kind) && validFrame($0.frame) &&
          ($0.frameSource.map { sources.contains($0) } ?? ($0.frame == nil)) &&
          ($0.font?.count ?? 0) <= 200 && ($0.fontSize.map { $0.isFinite && (1...400).contains($0) } ?? true)
      }
    }
    func decorations(_ values: [Decoration]) -> Bool {
      values.count <= 500 && Set(values.map(\.id)).count == values.count && values.allSatisfy { bounded($0.id) && bounded($0.kind) && validFrame($0.frame) }
    }
    return bounded(presentationPart) && (1...1_000_000_000).contains(widthEMU) && (1...1_000_000_000).contains(heightEMU) &&
      (0...500).contains(slideCount) && masters.count <= 50 && layouts.count <= 200 && masterIDs.count == masters.count && layoutIDs.count == layouts.count &&
      notices.count <= 20 && notices.allSatisfy { $0.count <= 300 } &&
      masters.allSatisfy { bounded($0.id) && placeholders($0.placeholders, sources: [$0.id]) && decorations($0.decorations) &&
        $0.textStyles.count <= 10 && $0.textStyles.values.allSatisfy { $0.isFinite && (1...400).contains($0) } } &&
      layouts.allSatisfy { bounded($0.id) && $0.name.count <= 200 && $0.kind.count <= 100 && masterIDs.contains($0.masterPart) &&
        (0...slideCount).contains($0.useCount) && placeholders($0.placeholders, sources: [$0.id, $0.masterPart]) && decorations($0.decorations) &&
        $0.notices.count <= 20 && $0.notices.allSatisfy { $0.count <= 300 } }
  }

  struct Frame: Codable, Hashable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int
  }

  struct Placeholder: Codable, Hashable, Identifiable {
    var index: String
    var kind: String
    var frame: Frame?
    var frameSource: String?
    var font: String?
    var fontSize: Double?
    var id: String { kind + ":" + index }
  }

  struct Decoration: Codable, Hashable, Identifiable {
    var id: String
    var kind: String
    var frame: Frame?
  }

  struct Theme: Codable, Hashable {
    var part: String
    var colors: [String: String]
    var headingFonts: [String: String]
    var bodyFonts: [String: String]
  }

  struct Master: Codable, Hashable, Identifiable {
    var id: String
    var theme: Theme?
    var colorMap: [String: String]
    var background: String?
    var placeholders: [Placeholder]
    var decorations: [Decoration]
    var textStyles: [String: Double]
  }

  struct Layout: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var kind: String
    var masterPart: String
    var useCount: Int
    var background: String?
    var placeholders: [Placeholder]
    var decorations: [Decoration]
    var notices: [String]
  }
}
