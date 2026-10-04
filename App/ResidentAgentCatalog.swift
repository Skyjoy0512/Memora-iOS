import Foundation

/// The resident agents offered to start from.
enum ResidentAgentCatalog {
  static let presets: [ResidentAgent] = [
    ResidentAgent(
      id: UUID(uuidString: "6F1D0C3E-2E5B-4C4E-9E0A-0D7A1B0F5A01")!,
      name: "朝のブリーフ",
      role: "その日の始まりに、やることと気をつけることを伝える",
      instructions: "期限が今日か過ぎている未完了のタスク、直近の会議で決まったこと、まだ決まっていないことを確認し、今日の要点を3〜5行で伝える。",
      symbol: .sunMax,
      trigger: .dailyMorning
    ),
    ResidentAgent(
      id: UUID(uuidString: "6F1D0C3E-2E5B-4C4E-9E0A-0D7A1B0F5A02")!,
      name: "会議フォロー",
      role: "会議が終わったら、後追いの漏れを防ぐ",
      instructions: "終わった会議の決まったこと・タスク・未決事項を確認し、担当や期限が抜けているもの、次に連絡すべき相手を挙げる。フォローアップのメール下書きなど、次にすべきことを提案する。",
      symbol: .checkmarkSeal,
      trigger: .afterMeeting
    ),
    ResidentAgent(
      id: UUID(uuidString: "6F1D0C3E-2E5B-4C4E-9E0A-0D7A1B0F5A03")!,
      name: "週次レビュー",
      role: "週の初めに、先週の振り返りと今週の注意点をまとめる",
      instructions: "先週の会議で決まったこと、終わったタスクと残っているタスク、持ち越しになっている未決事項をまとめ、今週気をつけることを3点挙げる。",
      symbol: .calendar,
      trigger: .weeklyMonday
    ),
    ResidentAgent(
      id: UUID(uuidString: "6F1D0C3E-2E5B-4C4E-9E0A-0D7A1B0F5A04")!,
      name: "メール見張り",
      role: "会議に関係するメールの見落としを防ぐ",
      instructions: "直近のメールから、会議の相手や案件に関係するものを探し、返信や対応が必要そうなものを挙げる。Gmailが連携されていなければ、そう伝えるだけにする。",
      symbol: .envelopeOpen,
      trigger: .dailyMorning
    )
  ]
}
