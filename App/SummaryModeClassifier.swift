import Foundation

/// What kind of input a summary is being written for.
///
/// The mode is decided from the shape of the input only. When the input
/// does not say clearly what it is, the mode is `unknown` and the existing
/// flow decides; a classifier never guesses.
enum SummaryMode: String, Codable, CaseIterable, Sendable {
  /// Prose that was written to be read: an article, a report, a document.
  case article
  /// Several people talking and deciding things.
  case meeting
  /// One voice explaining something in an order, to an audience.
  case lecture
  /// One voice talking, without a structure.
  case monologue
  /// The input does not say clearly what it is.
  case unknown

  /// The name shown in the interface.
  var title: String {
    switch self {
    case .article: "記事"
    case .meeting: "会議"
    case .lecture: "講演・講義"
    case .monologue: "独り言"
    case .unknown: "判定なし"
    }
  }
}

/// The shape of one input, read from the record itself.
///
/// Every field is a fact about the input, never an interpretation: how the
/// input arrived, whether it carries a link, how many people spoke and how
/// often the speaker changed, and whether the text is already structured.
struct SummaryModeFeatures: Equatable, Sendable {
  /// The input came from a recording or an imported audio file.
  var isAudio: Bool
  /// The input carries a web address.
  var hasURL: Bool
  /// How many different people spoke. Zero when the input has no speakers.
  var speakerCount: Int
  /// How often the speaker changed.
  var speakerTurnCount: Int
  /// The text has headings or bullet lines.
  var isStructured: Bool
  /// The text as it was read.
  var bodyText: String
}

/// Decides what kind of input a summary is for.
enum SummaryModeClassifier {
  /// The mode for one input.
  ///
  /// The rules are deliberately few and readable. An input that does not
  /// match one of them stays `unknown`, so the person or the existing flow
  /// decides instead of the classifier.
  static func classify(_ features: SummaryModeFeatures) -> SummaryMode {
    let body = features.bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !body.isEmpty else { return .unknown }

    guard features.isAudio else {
      return features.hasURL || features.isStructured ? .article : .unknown
    }

    if features.speakerCount >= 2 { return .meeting }
    guard features.speakerCount == 1 else { return .unknown }

    let strongCues = ["講義", "講演", "セミナー", "講座"]
    if strongCues.contains(where: { body.localizedStandardContains($0) }) {
      return .lecture
    }

    let longCues = ["今日は", "はじめに", "まとめ"]
    if body.count >= 400, longCues.contains(where: { body.localizedStandardContains($0) }) {
      return .lecture
    }

    return .monologue
  }

  /// The mode for a body of text on its own.
  ///
  /// A text with no speakers is an article when it carries a link or is
  /// structured, and stays `unknown` otherwise.
  static func classify(text: String, hasURL: Bool = false) -> SummaryMode {
    let isStructured = text.split(separator: "\n", omittingEmptySubsequences: false).contains {
      $0.hasPrefix("#") || $0.hasPrefix("- ") || $0.hasPrefix("* ")
    }
    return classify(SummaryModeFeatures(isAudio: false, hasURL: hasURL, speakerCount: 0,
      speakerTurnCount: 0, isStructured: isStructured, bodyText: text))
  }
}
