import Foundation

struct EditorDraftEnvelope: Codable {
  var baseline: [String: String]
  var values: [String: String]

  func restored(matching current: [String: String]) -> [String: String]? {
    baseline == current && Set(values.keys) == Set(current.keys) ? values : nil
  }
}
