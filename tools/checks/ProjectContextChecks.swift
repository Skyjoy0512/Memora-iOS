import Foundation

@main
struct ProjectContextChecks {
  static func main() throws {
    let project = UUID(), other = UUID()
    let source = ProjectCitation.Target.source(UUID())
    let secret = ProjectCitation.Target.source(UUID())
    let text = String(repeating: "箱根旅行の移動時間を短くする。", count: 100)
    let chunks = ProjectContextBuilder.split(text, projectID: project, target: source, title: "旅程", page: 2)
    precondition(chunks.count > 1 && chunks.allSatisfy { $0.text.count <= 700 && $0.page == 2 })
    let privateChunks = ProjectContextBuilder.split("機密事項", projectID: project, target: secret, title: "非公開")
    let otherChunks = ProjectContextBuilder.split("別プロジェクトの箱根旅行", projectID: other, target: source, title: "別件")
    for budget in [0, 20, 100, 500, 2_000] {
      let result = ProjectContextBuilder.build(question: "箱根の移動時間", projectID: project,
        chunks: chunks + privateChunks + otherChunks, allowed: [source], characterBudget: budget)
      precondition(result.text.count <= budget)
      precondition(!result.text.contains("機密事項") && !result.text.contains("別プロジェクト"))
      precondition(result.used.count <= 2)
      precondition(result.used.allSatisfy { $0.target == source && text.contains($0.excerpt) && $0.page == 2 })
    }
    let context = ProjectContextBuilder.build(question: "もっと短くして", projectID: project, chunks: chunks,
      allowed: [source], characterBudget: 1_000)
    precondition(!context.used.isEmpty)
    let citations = ProjectContextBuilder.cited("回答【資料1】【資料1】【資料99】", from: context.used)
    precondition(citations.count == 1 && citations[0] == context.used[0])
    let revoked = ProjectContextBuilder.build(question: "旅行", projectID: project, chunks: chunks,
      allowed: [], characterBudget: 1_000)
    precondition(revoked.used.isEmpty && revoked.text.isEmpty)
    let kana = ProjectContextBuilder.split("さくらの資料", projectID: project, target: source, title: "さくら")
    let kanaResult = ProjectContextBuilder.build(question: "さくら", projectID: project,
      chunks: kana, allowed: [source], characterBudget: 1_000)
    precondition(kanaResult.used.count == 1 && kanaResult.matchedCount == 1)
    for question in ["木星の衛星軌道", "ぬねのめも", "unrelated telescope"] {
      let unknown = ProjectContextBuilder.build(question: question, projectID: project,
        chunks: kana, allowed: [source], characterBudget: 1_000)
      precondition(unknown.used.isEmpty && unknown.matchedCount == 0)
    }
    let titleOnly = ProjectContextBuilder.split("本文は準備中", projectID: project, target: source, title: "保守契約")
    let titleResult = ProjectContextBuilder.build(question: "保守契約", projectID: project,
      chunks: titleOnly, allowed: [source], characterBudget: 1_000)
    precondition(titleResult.used.count == 1)
    let followUp = ProjectContextBuilder.build(question: "shorten that", projectID: project,
      chunks: kana, allowed: [source], characterBudget: 1_000)
    precondition(!followUp.used.isEmpty)
    let deadlines = ProjectContextBuilder.split("提出期限は金曜日", projectID: project, target: source, title: "作業")
    let paraphrase = ProjectContextBuilder.build(question: "納期は？", projectID: project,
      chunks: deadlines, allowed: [source], characterBudget: 1_000)
    precondition(paraphrase.used.count == 1)
    let selectedRead = ProjectContextBuilder.build(question: "承認について詳しく", projectID: project,
      chunks: kana + privateChunks + otherChunks, allowed: [source, secret], characterBudget: 1_000, selectedTarget: source)
    precondition(!selectedRead.used.isEmpty && selectedRead.used.allSatisfy { $0.target == source && $0.title == "さくら" })
    let revokedRead = ProjectContextBuilder.build(question: "承認について詳しく", projectID: project,
      chunks: kana, allowed: [], characterBudget: 1_000, selectedTarget: source)
    precondition(revokedRead.used.isEmpty)
    let overview = ProjectContextBuilder.build(question: "このプロジェクトの進捗をまとめて", projectID: project,
      chunks: kana + privateChunks + otherChunks, allowed: [source], characterBudget: 1_000)
    precondition(!overview.used.isEmpty && overview.used.allSatisfy { $0.target == source && $0.title == "さくら" })
    let duplicates = ProjectContextBuilder.build(question: "納期", projectID: project,
      chunks: deadlines + deadlines + deadlines, allowed: [source], characterBudget: 12_000)
    precondition(duplicates.used.count == 1 && duplicates.matchedCount == 1, "Duplicate chunks consumed source slots")
    let money = ProjectContextBuilder.split("予算は1,500円です。", projectID: project, target: source, title: "予算")
    let exactMoney = ProjectContextBuilder.build(question: "１５００円の予算", projectID: project,
      chunks: money, allowed: [source], characterBudget: 1_000)
    precondition(exactMoney.used.count == 1)
    let wrongMoney = ProjectContextBuilder.build(question: "50円の予算", projectID: project,
      chunks: money, allowed: [source], characterBudget: 1_000)
    precondition(wrongMoney.used.isEmpty)
    let recordedAt = Date(timeIntervalSince1970: 1_789_560_000)
    let meeting = ProjectCitation.Target.meeting(UUID())
    let datedChunks = ProjectContextBuilder.split("会議で公開方針を承認した。", projectID: project,
      target: meeting, title: "公開方針", time: 480, recordedAt: recordedAt)
    let dated = ProjectContextBuilder.build(question: "公開方針", projectID: project,
      chunks: datedChunks, allowed: [meeting], characterBudget: 300)
    let dateLabel = recordedAt.formatted(Date.FormatStyle(date: .numeric, time: .omitted).locale(Locale(identifier: "ja_JP")))
    precondition(dated.text.contains("記録日 \(dateLabel) · 録音内 480秒"))
    precondition(dated.used.first?.recordedAt == recordedAt && dated.used.first?.time == 480)
    precondition(citations[0].recordedAt == nil && !context.text.contains("記録日"))
    let legacyData = try JSONEncoder().encode(citations[0])
    precondition(!String(decoding: legacyData, as: UTF8.self).contains("recordedAt"))
    let legacyCitation = try JSONDecoder().decode(ProjectCitation.self, from: legacyData)
    precondition(legacyCitation == citations[0])
    let photo = ProjectCitation.Photo(name: "whiteboard.jpg", byteCount: 2_048,
      modifiedAt: recordedAt, textReadAt: recordedAt.addingTimeInterval(1))
    let photographed = ProjectContextBuilder.split("試験環境の接続仕様", projectID: project, target: meeting,
      title: "公開方針", recordedAt: recordedAt, photo: photo)
    let imageContext = ProjectContextBuilder.build(question: "接続仕様", projectID: project,
      chunks: datedChunks + photographed, allowed: [meeting], characterBudget: 500)
    precondition(imageContext.used.count == 1 && imageContext.used[0].photo == photo)
    precondition(imageContext.text.contains("写真の文字") && !imageContext.text.contains(photo.name))
    let recordPhotoContext = ProjectContextBuilder.build(question: "接続仕様", projectID: project,
      chunks: photographed + ProjectContextBuilder.split("試験環境の接続仕様と手順", projectID: project, target: meeting,
        title: "公開方針", recordedAt: recordedAt, photo: photo), allowed: [meeting], characterBudget: 500, marker: .photo)
    precondition(recordPhotoContext.text.hasPrefix("【写真1】") && !recordPhotoContext.text.contains("【資料1】"))
    precondition(recordPhotoContext.used.count == 1)
    let titleMatchOnly = ProjectContextBuilder.build(question: "公開方針", projectID: project,
      chunks: photographed, allowed: [meeting], characterBudget: 500)
    precondition(titleMatchOnly.used.isEmpty)
    let deniedPhoto = ProjectContextBuilder.build(question: "接続仕様", projectID: project,
      chunks: photographed, allowed: [], characterBudget: 500)
    precondition(deniedPhoto.used.isEmpty)
    precondition(ProjectContextBuilder.recordingDateQuery("会議日が２０２６年１１月５日の公開判定")?.topic == "公開判定")
    precondition(ProjectContextBuilder.recordingDateQuery("記録日: 2026-02-30") == nil)
    precondition(ProjectContextBuilder.recordingDateQuery("公開予定は2026年11月5日ですか？") == nil)
    precondition(ProjectContextBuilder.recordingDateQuery("記録日: 2026/11/05 と2026/11/12の変更点") == nil)
    let requested = ProjectContextBuilder.recordingDateQuery("録音日: 2026/11/05")!
    let startChunk = ProjectContextBuilder.split("対象日の記録", projectID: project,
      target: meeting, title: "対象日", recordedAt: requested.interval.start)
    let endChunk = ProjectContextBuilder.split("翌日の記録", projectID: project,
      target: meeting, title: "翌日", recordedAt: requested.interval.end)
    let byDay = ProjectContextBuilder.build(question: "録音日: 2026/11/05", projectID: project,
      chunks: startChunk + endChunk + kana, allowed: [source, meeting], characterBudget: 500)
    precondition(byDay.used.count == 1 && byDay.used[0].title == "対象日")
    print("ProjectContextChecks: passed (chunk/page/date fidelity, isolation, budgets, follow-ups, citations, hiragana/title search, no-match abstention, local aliases)")
  }
}
