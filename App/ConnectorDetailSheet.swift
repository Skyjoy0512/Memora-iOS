import SwiftUI

struct ConnectorDetailSheet: View {
  var service: IntegrationCatalog

  var body: some View {
    MarketplaceDetailSheet(item: .service(service))
  }
}
