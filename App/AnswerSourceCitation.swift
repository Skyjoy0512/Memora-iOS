import Foundation

/// A source identity, never a tool call or a permission grant.
enum AnswerSourceCitation {
  private static let pattern = /【(人物|タスク|メモ|記録|資料):([^【】\n]{0,128})】/
  private static let unfinished = /【(?:人物|タスク|メモ|記録|資料):[^【】\n]*$/

  static let instructions = """
  根拠にした情報の文末には、道具が返した出典マーカーをそのまま付けます。
  形式は【人物:UUID】【タスク:UUID】【メモ:UUID】【記録:UUID】【資料:UUID】です。
  読んだ対象の種類とIDだけを使い、IDや引用文を推測しません。名前の一致だけで人物を確定しません。
  マーカー以外に内部IDを書きません。マーカーは回答と資料本文に使い、メール本文やタスク名には含めません。
  """

  static func marker(for target: ArtifactSourceTarget) -> String {
    let (kind, id) = identity(target)
    let label: String = switch kind {
    case "person": "人物"
    case "task": "タスク"
    case "journal": "メモ"
    case "meeting": "記録"
    default: "資料"
    }
    return "【\(label):\(id.uuidString)】"
  }

  static func url(for target: ArtifactSourceTarget) -> URL {
    let (kind, id) = identity(target)
    return URL(string: "memora://source/\(kind)/\(id.uuidString)")!
  }

  static func target(for url: URL) -> ArtifactSourceTarget? {
    let parts = url.pathComponents.filter { $0 != "/" }
    guard url.scheme?.lowercased() == "memora", url.host?.lowercased() == "source", parts.count == 2,
          let id = UUID(uuidString: parts[1]), let target = target(kind: parts[0], id: id),
          url.absoluteString.lowercased() == self.url(for: target).absoluteString.lowercased() else { return nil }
    return target
  }

  static func targets(provenance: ArtifactProvenance?, meetingIDs: [UUID] = [], projectFileIDs: [UUID] = []) -> Set<ArtifactSourceTarget> {
    guard provenance?.isValid ?? true else { return [] }
    return Set((provenance?.records ?? []).map { .record($0.target) }
      + (provenance?.projectSources ?? []).map { .projectFile($0.id) }
      + meetingIDs.prefix(256).map { .record(.meeting($0)) }
      + projectFileIDs.prefix(32).map { .projectFile($0) })
  }

  static func linked(_ text: String, allowed: Set<ArtifactSourceTarget>) -> String {
    let linked = text.replacing(pattern) { match in
      guard let target = target(label: String(match.output.1), value: String(match.output.2)), allowed.contains(target) else { return "" }
      return "[↗\(target.label)の出典](\(url(for: target).absoluteString))"
    }
    return linked.replacing(unfinished) { _ in "" }
  }

  static func citedTargets(in text: String, allowed: Set<ArtifactSourceTarget>) -> [ArtifactSourceTarget] {
    var seen = Set<ArtifactSourceTarget>()
    return text.matches(of: pattern).compactMap { match in
      guard let target = target(label: String(match.output.1), value: String(match.output.2)),
            allowed.contains(target), seen.insert(target).inserted else { return nil }
      return target
    }
  }

  static func stripped(_ text: String) -> String {
    text.replacing(pattern) { _ in "" }.replacing(unfinished) { _ in "" }
  }

  private static func target(label: String, value: String) -> ArtifactSourceTarget? {
    guard let id = UUID(uuidString: value) else { return nil }
    switch label {
    case "人物": return .record(.person(id))
    case "タスク": return .record(.task(id))
    case "メモ": return .record(.journal(id))
    case "記録": return .record(.meeting(id))
    case "資料": return .projectFile(id)
    default: return nil
    }
  }

  private static func target(kind: String, id: UUID) -> ArtifactSourceTarget? {
    switch kind {
    case "person": .record(.person(id))
    case "task": .record(.task(id))
    case "journal": .record(.journal(id))
    case "meeting": .record(.meeting(id))
    case "file": .projectFile(id)
    default: nil
    }
  }

  private static func identity(_ target: ArtifactSourceTarget) -> (String, UUID) {
    switch target {
    case .record(.person(let id)): ("person", id)
    case .record(.task(let id)): ("task", id)
    case .record(.journal(let id)): ("journal", id)
    case .record(.meeting(let id)): ("meeting", id)
    case .projectFile(let id): ("file", id)
    }
  }
}
