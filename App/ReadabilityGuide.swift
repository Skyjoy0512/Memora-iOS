import Foundation

/// How Memora's summaries write Japanese so they read easily: meaning kept, who
/// did what said plainly, one topic per paragraph, sentences a breath long,
/// nothing padded. Summaries only; Ask AI answers keep their own voice, because
/// these rules read oddly in a conversation. Current with yomiyasu v1.0.7
/// (github.com/nanaism/yomiyasu, MIT) and k16shikano's Japanese technical
/// writing guide (gist.github.com/k16shikano, Unlicense); see
/// docs/THIRD_PARTY.md.
enum ReadabilityGuide {
  /// For cloud models, which have room for the whole guide.
  static let rules = """
  # 読みやすい日本語で書く
  意味を変えないことを最優先にする。書き直す前の「何を言っているか」「何を重く扱っているか」「言い切っているか推量か」「説明・依頼・評価のどれか」を、書き直した後も同じに保つ。
  - 主語・目的語・述語をそろえ、「誰が」「何を」したかを省かずに書く。「これ」「それ」ではなく、指す先が分かる具体的な名詞で書く。
  - 文の働き（説明・依頼・予定・評価）と、その強さ（断定・推量・可能性）を変えない。事実と予定、依頼と可能を混ぜない。原文にない主体・原因・条件・数値・感情を足さない。
  - 会議・資料・ツールなど人でないものを主語にして「〜が決めた」「〜が語る」のように擬人化しない。道具や仕組みの働きを客観的に述べる文はそのまま書く。
  - 比喩の動詞（壊れる・倒す・溶かす・効く・潰すなど）を使わず、実際に起きたこと・行うことをそのまま書く。ただし「骨が折れる」「手を焼く」など、ふつうの日本語で定着した慣用句はそのまま使う。
  - 前置き・まとめの決まり文句（「重要なのは〜」「結論から言うと」「いかがでしたでしょうか」）、二重否定、意味のない強調を書かない。評価を述べる文は、評価を述語に移して残す。
  - 否定対比（AではなくB）は、否定が意味や比重を担っているなら否定のまま残し、言い回しだけを整える。
  - 「資料を、全員へ。」のように、読点で間を置いたり短い句で切ったりするコピー調で書かない。主語・目的語から述語へ続けて読める文は一続きに書く。
  - ルールを「契約」、原文や比較の基準を「正本」のように、実際の役割より大げさな名詞を使わない。
  - 一つの段落には一つの話題だけを置き、段落の最初の文で何の話かが分かるようにする。
  - 一文はおよそ30〜45字、読点は0〜2個を目安にする。長い文は、目的・理由・順序のつながりを残せる範囲で分ける。
  - 違うものを「同じ」とまとめず、似た語を言い換えて増やさない。同じものは同じ語で呼ぶ。読み手が一度に覚えておくことは一つずつ増やす。
  """

  /// For the on-device model, whose window is small: the rules that matter most.
  static let compactRules = """
  書き方: 意味を変えず、誰が何をしたかを具体的な名詞で書く。事実と予定、依頼と可能を混ぜず、原文にない情報を足さない。一文は30〜45字ほどで、読点は2個まで。前置きや決まり文句を書かない。未定のことを断定しない。
  """
}
