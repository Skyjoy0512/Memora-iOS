import SwiftUI

struct SettingsValue: View {
  var title: String
  var value: String
  var icon: MemoraIcon

  var body: some View {
    LabeledContent {
      Text(value)
    } label: {
      SettingsLabel(title, icon: icon)
    }
  }
}
