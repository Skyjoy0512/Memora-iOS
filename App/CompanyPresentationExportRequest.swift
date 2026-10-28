import Foundation

/// Confirmation binds the operation to the exact document, template and workspace.
struct CompanyPresentationExportRequest: Identifiable, Equatable {
  var id = UUID()
  var document: MemoraDocument
  var template: CompanyTemplate
  var workspaceID: String?
  var generation: UUID

  var confirmationMessage: LocalizedStringResource {
    "書式「\(template.name)」v\(template.version)の原本に、編集済み\(document.slides.count)枚を追加した別ファイルを保存します。前回のPPTXは履歴に残り、外部送信はありません。"
  }
}
