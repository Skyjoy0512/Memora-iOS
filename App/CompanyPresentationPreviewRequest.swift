import Foundation

struct CompanyPresentationPreviewRequest: Identifiable {
  var id = UUID()
  var document: MemoraDocument
  var template: CompanyTemplate
  var workspaceID: String?
  var generation: UUID
}
