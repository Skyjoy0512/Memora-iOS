import Foundation

@main enum InlineCitationChecks {
  static func main() throws {
    let id = UUID(), otherID = UUID()
    let targets: [ArtifactSourceTarget] = [.record(.person(id)), .record(.task(id)), .record(.journal(id)), .record(.meeting(id)), .projectFile(id)]
    let allowed = Set(targets)
    for target in targets {
      let url = AnswerSourceCitation.url(for: target)
      precondition(AnswerSourceCitation.target(for: url) == target)
      precondition(AnswerSourceCitation.target(for: URL(string: url.absoluteString.lowercased())!) == target)
      for suffix in ["?account=other", "#other", "/extra", "/", "?", "#"] {
        precondition(AnswerSourceCitation.target(for: URL(string: url.absoluteString + suffix)!) == nil)
      }
    }
    for value in ["memora://source/person/not-a-uuid", "memora://user@source/person/\(id)",
                  "memora://source:80/person/\(id)", "https://source/person/\(id)",
                  "memora://source/unknown/\(id)", "memora://source/person/%41\(id)"] {
      precondition(AnswerSourceCitation.target(for: URL(string: value)!) == nil)
    }
    let text = targets.map { AnswerSourceCitation.marker(for: $0) }.joined(separator: " ")
    let linked = AnswerSourceCitation.linked(text, allowed: allowed)
    precondition(targets.allSatisfy { linked.contains(AnswerSourceCitation.url(for: $0).absoluteString) })
    precondition(AnswerSourceCitation.citedTargets(in: text + text, allowed: allowed) == targets)
    precondition(AnswerSourceCitation.stripped(text).trimmingCharacters(in: .whitespaces).isEmpty)
    precondition(AnswerSourceCitation.linked(text, allowed: []).trimmingCharacters(in: .whitespaces).isEmpty)
    let personOnly: Set<ArtifactSourceTarget> = [.record(.person(id))]
    precondition(AnswerSourceCitation.linked(AnswerSourceCitation.marker(for: .record(.task(id))), allowed: personOnly).isEmpty)
    for invalid in ["【人物:\(otherID)】", "【人物:invalid】", "【メモ:】", "【記録:../secret】"] {
      precondition(AnswerSourceCitation.linked(invalid, allowed: allowed).isEmpty)
    }
    for partial in ["【人物:", "【タスク:\(id.uuidString.prefix(12))", "【メモ:\(id)"] {
      precondition(AnswerSourceCitation.linked("本文" + partial, allowed: allowed) == "本文")
      precondition(AnswerCitations.stripped("本文" + partial) == "本文")
    }
    let first = AIChatSource(meetingID: UUID(), title: "未許可")
    let second = AIChatSource(meetingID: id, title: "資料[見出し]\\\n(確認)*")
    precondition(!AnswerCitations.hasCitations("【資料1】", sources: [first], allowedTargets: []))
    precondition(AnswerCitations.hasCitations(text, sources: [], allowedTargets: allowed))
    precondition(!AnswerCitations.hasCitations(text, sources: [], allowedTargets: []))
    let mixed = AnswerCitations.linked("会議【資料1】と会議【資料2】と人物" + AnswerSourceCitation.marker(for: .record(.person(id))),
      sources: [first, second], allowedTargets: allowed)
    precondition(!mixed.contains("memora-cite://1") && mixed.contains("memora-cite://2") && mixed.contains("\\[見出し\\]"))
    precondition(AnswerCitations.source(for: URL(string: "memora-cite://2")!, in: [first, second]) == second)
    for value in ["memora-cite://2/extra", "memora-cite://2?x=1", "memora-cite://02", "memora-cite://0", "memora-cite://99"] {
      precondition(AnswerCitations.source(for: URL(string: value)!, in: [first, second]) == nil)
    }
    let provenance = ArtifactProvenance(sourceMessageID: UUID(), records: targets.compactMap { target in
      guard case .record(let record) = target else { return nil }
      return AIRecordReference(target: record, fingerprint: String(repeating: "a", count: 64))
    }, projectSources: [.init(id: id, projectID: nil, fingerprint: String(repeating: "b", count: 64))])
    precondition(AnswerSourceCitation.targets(provenance: provenance) == allowed)
    var invalid = provenance
    invalid.records.append(invalid.records[0]); precondition(AnswerSourceCitation.targets(provenance: invalid, meetingIDs: [id]).isEmpty)

    var message = AIChatMessage(role: .assistant, text: "# 確認事項\n\n" + text + "\n会議【資料1】\n不明【タスク:\(otherID)】")
    message.sources = [second]; message.artifactProvenance = provenance
    let document = AIAnswerDocumentBuilder.make(message: message, question: "田中さんとの確認事項")
    precondition(document.provenance == provenance && document.sourceProjectFileIDs == [id] && document.sourceRecordIDs == [id])
    precondition(!document.markdown.contains(otherID.uuidString) && !document.markdown.contains("【人物:"))
    precondition(targets.allSatisfy { document.markdown.contains(AnswerSourceCitation.url(for: $0).absoluteString) })
    precondition(document.markdown.contains(MeetingLink.url(for: id)!.absoluteString))
    let restored = try JSONDecoder().decode(MemoraDocument.self, from: JSONEncoder().encode(document))
    precondition(restored == document)
    let snapshot = AIConversationSnapshot(messages: [message], workspaceID: nil)
    let restoredMessage = try AIConversationSnapshot.decode(JSONEncoder().encode(snapshot), workspaceID: nil).restoredMessages()[0]
    precondition(restoredMessage.artifactProvenance == provenance && restoredMessage.cloudAuthorizationTargets == nil)
    let rebuilt = AIAnswerDocumentBuilder.make(message: restoredMessage, question: "田中さんとの確認事項")
    precondition(rebuilt.markdown == document.markdown)
    let long = String(repeating: text + " ", count: 1_000)
    precondition(AnswerSourceCitation.citedTargets(in: long, allowed: allowed) == targets)
    precondition(!AnswerCitations.linked(long, sources: [], allowedTargets: []).contains(id.uuidString))

    // Retrieved project-source citations become openable only while the exact
    // evidence they were read from still exists.
    func projectCitation(_ source: UUID, reference: String? = nil, fingerprint: String? = nil) -> ProjectCitation {
      ProjectCitation(target: .source(source), title: "資料", excerpt: "本文",
        evidenceReference: reference, evidenceFingerprint: fingerprint)
    }
    let sourceID = UUID()
    let readable = ProjectCitationTargets.Evidence(isReadable: true, reference: "text-v1", fingerprint: "hash-1")
    precondition(ProjectCitationTargets.live([], evidence: { _ in readable }).isEmpty)
    precondition(ProjectCitationTargets.live([projectCitation(sourceID, reference: "text-v1", fingerprint: "hash-1")]) { _ in readable }
      == [.projectFile(sourceID)])
    precondition(ProjectCitationTargets.live([projectCitation(sourceID)]) { _ in readable }
      == [.projectFile(sourceID)], "legacy citation without a stamp stays readable")
    precondition(ProjectCitationTargets.live([projectCitation(sourceID, reference: "text-v0")]) { _ in readable }.isEmpty)
    precondition(ProjectCitationTargets.live([projectCitation(sourceID, fingerprint: "hash-0")]) { _ in readable }.isEmpty)
    precondition(ProjectCitationTargets.live([projectCitation(sourceID)]) { _ in
      ProjectCitationTargets.Evidence(isReadable: false, reference: "text-v1", fingerprint: "hash-1")
    }.isEmpty)
    precondition(ProjectCitationTargets.live([projectCitation(sourceID)]) { _ in nil }.isEmpty)
    precondition(ProjectCitationTargets.live([
      projectCitation(sourceID), projectCitation(sourceID),
      ProjectCitation(target: .meeting(UUID()), title: "録音", excerpt: "本文")
    ]) { _ in readable } == [.projectFile(sourceID)])
    precondition(ProjectCitationTargets.live([projectCitation(sourceID)]) { _ in
      ProjectCitationTargets.Evidence(isReadable: true, reference: "text-v1", fingerprint: nil)
    } == [.projectFile(sourceID)], "a source without a fingerprint is compared by reference only")

    // A saved grounded answer keeps the project-source link it was read from.
    var grounded = AIChatMessage(role: .assistant,
      text: "回答です " + AnswerSourceCitation.marker(for: .projectFile(sourceID)))
    grounded.sourceCitations = [projectCitation(sourceID)]
    let groundedDocument = AIAnswerDocumentBuilder.make(message: grounded, question: "質問")
    precondition(groundedDocument.sourceProjectFileIDs == [sourceID])
    precondition(groundedDocument.markdown.contains(AnswerSourceCitation.url(for: .projectFile(sourceID)).absoluteString))
    precondition(groundedDocument.markdown.contains("参照した情報"))

    print("InlineCitationChecks: passed (production parser/URL/legacy formatting/document builder/snapshot, typed UUID collisions, forged IDs and URL variants, unfinished stream markers, label escaping, saved links, bounded source sets, project-source evidence stamping/revocation and saved grounded links, 5000 markers; no network)")
  }
}
