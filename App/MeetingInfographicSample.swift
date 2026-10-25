import Foundation

/// Only the explicitly fictional, unedited display sample gets this fixture.
enum MeetingInfographicSample {
  static func resolve(_ snapshot: MeetingSummaryPosterSnapshot) -> MeetingInfographic? {
    if let saved = MeetingInfographic.decode(snapshot.infographicJSON, meetingID: snapshot.meetingID,
      summary: snapshot.summary, privacy: snapshot.privacy) { return saved }
    guard snapshot.infographicJSON == nil, snapshot.meetingID == SummarizedAudioSample.id,
          snapshot.summary == SummarizedAudioSample.summary else { return nil }
    let content = Self.content
    guard (try? content.validate(against: snapshot.summary)) != nil else { return nil }
    return MeetingInfographic(meetingID: snapshot.meetingID, sourceSummary: snapshot.summary, privacy: snapshot.privacy,
      modelLabel: "表示サンプル（AI生成は未実行）", generatedAt: snapshot.createdAt, content: content)
  }

  static var content: MeetingInfographic.Content {
    MeetingInfographic.Content(
      headline: .init(label: "公開に向けた判断軸", text: "先に5人で検証し、結果を見て公開日を決める", evidence: "先に5人で検証し、結果を見て公開日を決める"),
      panels: [
        .init(title: "つまずきの構造", kind: .flow, items: [
          .init(label: "見え方", text: "録音ボタンより先に設定が目に入る。", evidence: "録音ボタンより先に設定が目に入る。"),
          .init(label: "受け取り方", text: "初めて使う人が、録音前に設定を終える必要があると受け取った。", evidence: "初めて使う人が、録音前に設定を終える必要があると受け取った。")]),
        .init(title: "初回設定と同意説明", kind: .comparison, items: [
          .init(label: "変えること", text: "初回設定を録音後へ", evidence: "初回の設定を録音後へ移す"),
          .init(label: "守ること", text: "利用目的・同意は録音前に", evidence: "マイクの利用目的と録音への同意は、開始前に伝える。")]),
        .init(title: "判断に必要な検証", kind: .metric, items: [
          .init(label: "先行テスト", text: "5人", evidence: "先に5人で検証し、結果を見て公開日を決める"),
          .init(label: "現在地", text: "改善の効果はまだ確認できていない。", evidence: "改善の効果はまだ確認できていない。")]),
        .init(title: "検証までの準備", kind: .timeline, items: [
          .init(label: "10月28日 · 田中", text: "初回録音フローを試作", evidence: "| 初回録音フローの試作 | 設定を録音後へ移す案を作る | 田中 | 10月28日 |"),
          .init(label: "10月29日 · 佐藤", text: "同意説明を含む検証を調整", evidence: "| 5人の検証日程を調整 | 同意説明を含む一連の操作を確認する | 佐藤 | 10月29日 |")])
      ], questions: ["5人での検証で、何を確認すれば公開を判断できそう？", "録音前に残す同意説明と、録音後へ移す設定を整理して", "田中さんと佐藤さんの準備作業に、抜けや依存関係はある？"])
  }
}
