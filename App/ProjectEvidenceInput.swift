import Foundation
import Darwin

struct ProjectEvidenceInput: Codable, Equatable, Sendable {
  var target: ProjectCitation.Target
  var title: String
  var blocks: [ProjectSourceText]
  var recordedAt: Date?

  /// JSON fingerprints distinguish canonically equivalent Unicode and signed
  /// zero. Cache hits must preserve that same exact-content boundary.
  static func == (lhs: Self, rhs: Self) -> Bool {
    guard lhs.target == rhs.target, sameBytes(lhs.title, rhs.title),
          lhs.recordedAt == rhs.recordedAt, lhs.blocks.count == rhs.blocks.count else { return false }
    return zip(lhs.blocks, rhs.blocks).allSatisfy { left, right in
      left.page == right.page && left.time?.bitPattern == right.time?.bitPattern
        && sameBytes(left.text, right.text)
    }
  }

  private static func sameBytes(_ lhs: String, _ rhs: String) -> Bool {
    let direct = lhs.utf8.withContiguousStorageIfAvailable { left in
      rhs.utf8.withContiguousStorageIfAvailable { right in
        guard left.count == right.count else { return false }
        guard let leftBase = left.baseAddress, let rightBase = right.baseAddress else { return left.isEmpty }
        return memcmp(leftBase, rightBase, left.count) == 0
      }
    }
    if let available = direct, let equal = available { return equal }
    return lhs.utf8.elementsEqual(rhs.utf8)
  }
}
