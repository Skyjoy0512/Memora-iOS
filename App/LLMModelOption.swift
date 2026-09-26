import Foundation

/// One model a provider offers: the id sent in the request and how it reads.
struct LLMModelOption: Identifiable, Hashable, Sendable {
  var id: String
  var name: String
  var detail: String?
}
