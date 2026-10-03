import Foundation

// Building the glossary from the person's mail: who they write to and the
// companies and products that keep coming up. Read through Gmail and picked
// out on the device; the mail never goes to an AI for this.
extension MemoraModel {
  func glossaryCandidatesFromMail() async throws -> [GlossaryCandidate] {
    let gmail = GmailService.shared
    let sent = try await gmail.search("in:sent newer_than:180d", limit: 40)
    let received = try await gmail.search(
      "in:inbox newer_than:90d -category:promotions -category:social -category:updates -category:forums",
      limit: 40
    )
    return GlossaryCandidateExtractor.candidates(
      sent: sent,
      received: received,
      excluding: glossaryTerms + people.map(\.name) + spaces.map(\.name)
    )
  }

  func addGlossaryTerms(_ terms: [String]) {
    for term in terms {
      addGlossaryTerm(term)
    }
  }
}
