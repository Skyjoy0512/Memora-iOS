import SwiftUI

struct ToolbarActionGap: ToolbarContent {
  var body: some ToolbarContent {
    if #available(iOS 26.0, *) {
      ToolbarSpacer(.fixed, placement: .topBarTrailing)
    }
  }
}
