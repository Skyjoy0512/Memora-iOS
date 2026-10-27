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

  static func plan(_ json: String, slides: [DocumentSlide]) throws -> PresentationPlan {
    guard json.utf8.count <= 50_000, let data = json.data(using: .utf8),
          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          Set(object.keys).isSubset(of: ["purpose", "audience", "decision", "assumptions", "storyline"]) else {
      throw Failure(message: "資料計画は50KB以内の既知のJSON項目で指定してください。")
    }
    struct Input: Decodable {
      var purpose: String
      var audience: String
      var decision: String
      var assumptions: [String]
      var storyline: [Point]
      struct Point: Decodable {
        var slide_number: Int
        var claim: String
        var evidence: [String]
        var unconfirmed: [String]
      }
    }
    let input = try JSONDecoder().decode(Input.self, from: data)
    guard input.storyline.allSatisfy({ (1...max(1, slides.count)).contains($0.slide_number) && $0.slide_number <= slides.count }) else {
      throw Failure(message: "資料計画のスライド番号が範囲外です。")
    }
    let plan = PresentationPlan(purpose: input.purpose, audience: input.audience, decision: input.decision,
      assumptions: input.assumptions, storyline: input.storyline.map {
        .init(slideID: slides[$0.slide_number - 1].id, claim: $0.claim, evidence: $0.evidence, unconfirmed: $0.unconfirmed)
      })
    guard plan.isValid(for: slides) else { throw Failure(message: "資料計画の重複・文字数・主張を確認してください。") }
    return plan
  }
}
