import Foundation

/// How Memora's AI writes Japanese so it reads easily: who did what said
/// plainly, one topic per paragraph, sentences a breath long, nothing padded.
/// Drawn from yomiyasu (github.com/nanaism/yomiyasu, MIT) and k16shikano's
/// Japanese technical writing guide (gist.github.com/k16shikano, Unlicense);
/// see docs/THIRD_PARTY.md.
enum ReadabilityGuide {
  /// For cloud models, which have room for the whole guide.
  static let rules = """
  # 読みやすい日本語で書く
  - 主語・目的語・述語をそろえる。「誰が」「何を」したかを省かず、「これ」「それ」ではなく具体的な名詞で書く。
  - 依頼（〜してください）と可能（〜できます）、事実と予定を混ぜない。
  - 会議・資料・ツールなど人でないものを主語にして「〜が決めた」「〜が語る」のように擬人化しない。
  - 比喩の動詞（壊れる・走る・運ぶなど）を使わず、実際に起きたこと・行うことをそのまま書く。
  - 前置き・まとめの決まり文句（「重要なのは〜」「結論から言うと」「本質的には」）、二重否定、意味のない強調を書かない。
  - 一つの段落には一つの話題だけを置き、段落の最初の文で何の話かが分かるようにする。
  - 一文はおよそ30〜45字、読点は0〜2個を目安にし、長い文は分ける。
  - 推量・可能性・未定のことを断定に変えない。根拠のない注意書きや一般論を足さない。
  - 違うものを「同じ」とまとめず、似た語を言い換えて増やさない。同じものは同じ語で呼ぶ。
  - 読み手が一度に覚えておくことは一つずつ増やす。
  - 結論や重要な決定を先に書き、その後に根拠や詳細を置く。
  - 1段落は2〜3文を目安にし、話題が変わるところで空行を入れる。表示幅に合わせた手動改行は入れない。
  - 決定・変更点・期限など拾い読みしたい短い語句だけを **太字** にする。文全体や段落全体を太字にしない。
  - 箇条書きは1項目1論点。長い回答は短い見出しで分け、同じ内容を概要と本文で繰り返しすぎない。
  """

  /// For the on-device model, whose window is small: the rules that matter most.
  static let compactRules = """
  書き方: 結論から書く。誰が何をしたかを具体的な名詞で書く。一文は30〜45字ほど。話題の間に空行を入れ、重要な短い語句だけを太字にする。前置きや決まり文句を書かない。未定のことを断定しない。
  """
}
