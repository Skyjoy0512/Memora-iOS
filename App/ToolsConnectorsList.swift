import SwiftUI

struct ToolsConnectorsList: View {
  @Binding var query: String
  var body: some View { ConnectorHubView(query: query, showsIntroduction: false) }
}
