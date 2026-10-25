import Foundation

/// Conservative lexical evidence, not an assertion that a model's interpretation
/// is true. Keep units/signs/dates attached; never match a suffix of a number.
enum GroundedQuantity {
  private static let quantities = try! NSRegularExpression(pattern:
    #"(?:[0-9]{2,4}[/-][0-9]{1,2}(?:[/-][0-9]{1,2})?|[0-9]{1,2}:[0-9]{2}(?::[0-9]{2})?|[0-9]+年[0-9]+月(?:[0-9]+日)?|[0-9]+月[0-9]+日|[¥$€£]?\s*[+−-]?[0-9][0-9,]*(?:\.[0-9]+)?\s*(?:兆|億|万|千)?\s*(?:パーセント|ポイント|ドル|ユーロ|万円|円|名|人|件|個|社|回|倍|%|年|月|日|時間|時|分|秒|[A-Za-zµμ°]+|[\p{Han}]+)?)"#)
  private static let number = try! NSRegularExpression(pattern: #"[0-9][0-9,]*(?:\.[0-9]+)?"#)
  private static let grouped = try! NSRegularExpression(pattern: #"^[0-9]{1,3}(?:,[0-9]{3})+(?:\.[0-9]+)?$"#)
  private static let relational = ["増", "減", "上回", "下回", "以上", "以下", "未満", "より", "対し", "最大", "最小",
    "予定", "見込", "未定", "未確定", "検討", "提案", "条件", "場合", "なら", "ない", "なかった", "せず", "否定", "却下", "ため", "によって", "を受けて"]

  static func supports(_ claim: String, in evidence: String) -> Bool {
    guard let claims = tokens(claim), let sources = tokens(evidence) else { return false }
    return claims.allSatisfy { sources.contains($0) }
  }

  static func preservesQualification(_ claim: String, in evidence: String, considersEvidence: Bool = true) -> Bool {
    let claim = normalized(claim), evidence = normalized(evidence)
    if relational.contains(where: { claim.contains($0) || (considersEvidence && evidence.contains($0)) }) {
      // Matching quantities alone cannot prove direction, negation or certainty.
      // A quotation is preferable to accepting an unverifiable paraphrase here.
      return evidence.contains(claim) && (!considersEvidence || relational.filter { evidence.contains($0) }.allSatisfy { claim.contains($0) })
    }
    return true
  }

  private static func tokens(_ text: String) -> Set<String>? {
    let value = normalized(text)
    let string = value as NSString
    var result: Set<String> = []
    for match in quantities.matches(in: value, range: NSRange(location: 0, length: string.length)) {
      var token = string.substring(with: match.range).replacingOccurrences(of: " ", with: "")
      for numeric in number.matches(in: token, range: NSRange(location: 0, length: (token as NSString).length)) {
        let raw = (token as NSString).substring(with: numeric.range)
        if raw.contains(","), grouped.firstMatch(in: raw, range: NSRange(location: 0, length: (raw as NSString).length)) == nil { return nil }
      }
      token = token.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "パーセント", with: "%")
      result.insert(token)
    }
    return result
  }

  private static func normalized(_ text: String) -> String {
    text.precomposedStringWithCompatibilityMapping.replacingOccurrences(of: "**", with: "")
      .replacingOccurrences(of: "−", with: "-")
      .split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }
}
