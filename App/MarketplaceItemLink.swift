import SwiftUI

struct MarketplaceItemLink<Label: View>: View {
  var item: MarketplaceItem
  var onConnectorDismiss: (() -> Void)?
  @ViewBuilder var label: () -> Label
  @State private var showsConnector = false

  var body: some View {
    if case .service(let service) = item {
      Button { showsConnector = true } label: { label() }
        .sheet(isPresented: $showsConnector, onDismiss: onConnectorDismiss) { ConnectorDetailSheet(service: service) }
    } else {
      NavigationLink { item.destination } label: { label() }
    }
  }
}
