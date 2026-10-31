import SwiftUI

struct ConnectorDetailSheet: View {
  @Environment(\.dismiss) private var dismiss
  var service: IntegrationCatalog

  var body: some View {
    NavigationStack {
      IntegrationDetailView(service: service)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            ToolbarIconButton("閉じる", icon: .xmark) { dismiss() }
          }
        }
    }
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
  }
}
