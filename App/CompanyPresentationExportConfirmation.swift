import SwiftUI

struct CompanyPresentationExportConfirmation: ViewModifier {
  @Binding var isPresented: Bool
  var request: CompanyPresentationExportRequest?
  var perform: (CompanyPresentationExportRequest) -> Void

  func body(content: Content) -> some View {
    content.confirmationDialog("会社PPTXを書き出しますか？", isPresented: $isPresented, titleVisibility: .visible, presenting: request) { request in
      Button("書き出す") { perform(request) }
        .accessibilityIdentifier("presentation.companyExport.confirm")
      Button("キャンセル", role: .cancel) {}
    } message: { request in Text(request.confirmationMessage) }
  }
}
