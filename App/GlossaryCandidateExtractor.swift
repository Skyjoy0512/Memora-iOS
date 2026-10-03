import Foundation

/// Finds glossary candidates in mail headers and opening lines: the names of
/// people written to, company names, and product or service names that keep
/// coming up. Pure and on-device; nothing is sent anywhere.
enum GlossaryCandidateExtractor {
  static func candidates(
    sent: [GmailMessage],
    received: [GmailMessage],
    excluding known: [String]
  ) -> [GlossaryCandidate] {
    let knownKeys = Set(known.map { $0.lowercased() })
    var counts: [String: (kind: GlossaryCandidate.Kind, count: Int)] = [:]

    func add(_ terms: Set<String>, as kind: GlossaryCandidate.Kind) {
      for term in terms where !knownKeys.contains(term.lowercased()) {
        let existing = counts[term]
        counts[term] = (existing?.kind ?? kind, (existing?.count ?? 0) + 1)
      }
    }

    // People the person writes to count from one mail; the rest need a pattern.
    for message in sent {
      add(Set(names(in: message.to)), as: .person)
    }
    for message in sent + received {
      let text = [message.subject, message.snippet, message.from, message.to].joined(separator: "\n")
      add(Set(companies(in: text)), as: .company)
      add(Set(terms(in: [message.subject, message.snippet].joined(separator: "\n"))), as: .term)
    }

    return counts
      .filter { term, value in
        switch value.kind {
        case .person: return value.count >= 1
        case .company: return value.count >= 1
        case .term: return value.count >= 2 && term.count >= 3
        }
      }
      .map { GlossaryCandidate(term: $0.key, kind: $0.value.kind, count: $0.value.count) }
      .sorted { $0.count != $1.count ? $0.count > $1.count : $0.term < $1.term }
      .prefix(60)
      .map { $0 }
  }

  /// Display names from an address list: `"田中 太郎" <a@b>, Sato <c@d>`.
  static func names(in header: String) -> [String] {
    header.split(separator: ",").compactMap { part in
      guard let bracket = part.firstIndex(of: "<") else { return nil }
      let name = part[..<bracket]
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
      let lower = name.lowercased()
      guard name.count >= 2, name.count <= 30, !name.contains("@"),
            !["noreply", "no-reply", "info", "support", "notification", "team", "admin"].contains(where: lower.contains) else {
        return nil
      }
      return name
    }
  }

  static func companies(in text: String) -> [String] {
    // A company name is katakana, kanji, letters and digits; hiragana marks
    // where the sentence goes on (アルファの田中様 → アルファ).
    let name = "[ァ-ヴー・A-Za-z0-9＆&\\p{Han}]{1,16}"
    let pattern = "(?:株式会社|有限会社|合同会社)\(name)|\(name)(?:株式会社|有限会社|合同会社)"
    return matches(of: pattern, in: text)
  }

  /// Katakana words and capitalised English names that are not everyday words.
  static func terms(in text: String) -> [String] {
    let katakana = matches(of: "[ァ-ヴー・]{4,}", in: text).filter { !commonKatakana.contains($0) }
    // Bounded by anything that is not a Latin letter or digit, so a name
    // written straight before Japanese (Salesforce連携) is still found.
    let english = matches(of: "(?<![A-Za-z0-9])[A-Z][A-Za-z0-9]{2,}(?:[ \\-][A-Z][A-Za-z0-9]{2,}){0,2}(?![A-Za-z0-9])", in: text)
      .filter { !commonEnglish.contains($0.lowercased()) }
    let acronyms = matches(of: "(?<![A-Za-z0-9])[A-Z]{2,6}(?![A-Za-z0-9])", in: text)
      .filter { !commonEnglish.contains($0.lowercased()) }
    return katakana + english + acronyms
  }

  private static func matches(of pattern: String, in text: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(text.startIndex..., in: text)
    return regex.matches(in: text, range: range).compactMap { match in
      Range(match.range, in: text).map { String(text[$0]).trimmingCharacters(in: .whitespaces) }
    }
  }

  private static let commonKatakana: Set<String> = [
    "ミーティング", "スケジュール", "プロジェクト", "アカウント", "パスワード", "サービス", "キャンペーン",
    "ニュースレター", "セミナー", "リマインダー", "アップデート", "ダウンロード", "クリック", "システム",
    "ファイル", "コメント", "レポート", "メンバー", "オンライン", "サポート", "カレンダー", "イベント",
    "セキュリティ", "プライバシー", "ポリシー", "ユーザー", "クーポン", "ポイント", "ショッピング",
    "コンテンツ", "ニュース", "メッセージ", "アドレス", "スタッフ", "フォーム", "ログイン", "メールアドレス",
    "プレゼント", "キャンセル", "サンプル", "テンプレート", "ドキュメント", "スライド", "フォロー", "アップ"
  ]

  private static let commonEnglish: Set<String> = [
    "re", "fw", "fwd", "the", "and", "for", "you", "your", "cc", "bcc", "pm", "am", "url", "pdf", "http",
    "https", "html", "ok", "mtg", "asap", "fyi", "faq", "mon", "tue", "wed", "thu", "fri", "sat", "sun",
    "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec", "inc", "ltd", "llc",
    "hello", "thanks", "thank", "best", "regards", "dear", "hi", "new", "this", "that", "with", "from",
    "jp", "com", "co", "id", "no", "tel", "fax", "web", "app", "ai", "it", "q", "us", "uk", "eu"
  ]
}
