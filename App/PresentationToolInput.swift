import Foundation

/// Untrusted model output is bounded and decoded before the existing approval/save path.
enum PresentationToolInput {
  struct Failure: LocalizedError {
    var message: String
    var errorDescription: String? { message }
  }

  static func slide(_ input: [String: Any]) throws -> DocumentSlide {
    var slide = DocumentSlide(title: (input["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
      bullets: (input["bullets"] as? [String]) ?? [], notes: input["notes"] as? String ?? "")
    guard let raw = input["layout"] as? String, !raw.isEmpty else {
      guard input["content_json"] == nil else { throw Failure(message: "layoutのない構造化データは保存できません。") }
      return slide
    }
    guard let layout = SlideArchetype(rawValue: raw), let json = input["content_json"] as? String,
          json.utf8.count <= 100_000, let data = json.data(using: .utf8),
          var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw Failure(message: "レイアウトIDと100KB以内のcontent_jsonを確認してください。")
    }
    let allowed: Set<String> = ["layout", "subtitle", "items", "table", "metrics", "chart", "diagram", "schedule", "annotations", "sources"]
    guard Set(object.keys).isSubset(of: allowed) else { throw Failure(message: "未知のスライド項目があります。") }
    if let inner = object["layout"] as? String, inner != raw { throw Failure(message: "レイアウトIDが一致していません。") }
    object["layout"] = layout.rawValue
    for key in ["items", "metrics"] {
      if let entries = object[key] as? [[String: Any]] { object[key] = withIDs(entries) }
    }
    if var schedule = object["schedule"] as? [String: Any], let entries = schedule["entries"] as? [[String: Any]] {
      schedule["entries"] = withIDs(entries); object["schedule"] = schedule
    }
    slide.composition = try JSONDecoder().decode(SlideContent.self, from: JSONSerialization.data(withJSONObject: object))
    // Both representations may carry different assertions. Structured slides have one body.
    guard slide.bullets.isEmpty else { throw Failure(message: "構造化スライドの本文はcontent_jsonへまとめ、bulletsは空にしてください。") }
    let errors = PresentationValidator.issues(for: slide).filter(\.isError)
    guard errors.isEmpty else { throw Failure(message: errors.prefix(5).map(\.message).joined(separator: "\n")) }
    return slide
  }

  private static func withIDs(_ values: [[String: Any]]) -> [[String: Any]] {
    values.map { value in
      var value = value
      value["id"] = UUID().uuidString
      return value
    }
  }
}
