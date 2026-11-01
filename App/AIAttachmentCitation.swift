import Foundation

struct AIAttachmentCitation: Codable, Hashable, Sendable {
  var number: Int
  var file: AIAttachmentFileReference
  var excerpt: String
  var page: Int?
  var time: TimeInterval?

  private enum CodingKeys: String, CodingKey {
    case number, file, excerpt, page, time
  }

  init?(number: Int, file: AIAttachmentFileReference, excerpt: String, page: Int? = nil, time: TimeInterval? = nil) {
    self.number = number
    self.file = file
    self.excerpt = excerpt
    self.page = page
    self.time = time
    guard isValid else { return nil }
  }

  var isValid: Bool {
    (1...64).contains(number) && file.isValid && file.additionalFiles == nil &&
      !excerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && excerpt.utf8.count <= 8_000 &&
      (page.map { $0 > 0 } ?? true) &&
      (time.map { $0.isFinite && $0 >= 0 && $0 <= 7 * 24 * 60 * 60 } ?? true)
  }

  var marker: String { "【添付\(number)】" }

  var contextText: String {
    let safeTime = time.flatMap { $0.isFinite && $0 >= 0 && $0 <= 7 * 24 * 60 * 60 ? $0 : nil }
    let location = page.map { " · ページ\($0)" } ?? safeTime.map { " · \(Int($0))秒" } ?? ""
    return marker + location + "\n" + excerpt
  }

  /// A marker alone is insufficient when a downstream budget cuts its excerpt.
  static func retained(_ citations: [Self], in context: String) -> [Self] {
    var seen = Set<Int>()
    return Array(citations.filter { citation in
      citation.isValid && context.range(of: citation.contextText, options: .literal) != nil && seen.insert(citation.number).inserted
    }.prefix(64))
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    number = try values.decode(Int.self, forKey: .number)
    file = try values.decode(AIAttachmentFileReference.self, forKey: .file)
    excerpt = try values.decode(String.self, forKey: .excerpt)
    page = try values.decodeIfPresent(Int.self, forKey: .page)
    time = try values.decodeIfPresent(TimeInterval.self, forKey: .time)
    guard isValid else {
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid attachment evidence"))
    }
  }
}
