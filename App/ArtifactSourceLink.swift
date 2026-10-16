import SwiftUI

struct ArtifactSourceLink: View {
  var row: ArtifactSourceRow
  var open: () -> Void

  var body: some View {
    Button(action: open) {
      HStack(alignment: .top, spacing: 10) {
        Image(icon: row.target.icon).frame(width: 20).accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 3) {
          Text(row.title).frame(maxWidth: .infinity, alignment: .leading)
          Text(row.target.label + " · " + row.status).font(.caption).foregroundStyle(.secondary)
        }
        if row.canOpen { Image(icon: .chevronRight).font(.caption).accessibilityHidden(true) }
      }
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!row.canOpen)
    .accessibilityElement(children: .combine)
    .accessibilityHint(row.canOpen ? "元の情報を開きます" : "")
  }
}
