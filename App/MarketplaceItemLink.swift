import SwiftUI

struct MarketplaceItemLink<Label: View>: View {
  var item: MarketplaceItem
  var onConnectorDismiss: (() -> Void)?
  @ViewBuilder var label: () -> Label
  @State private var showsDetail = false

  var body: some View {
    Button { showsDetail = true } label: { label() }
      .sheet(isPresented: $showsDetail, onDismiss: onConnectorDismiss) { MarketplaceDetailSheet(item: item) }
  }
}
