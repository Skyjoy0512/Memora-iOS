import SwiftUI

struct OpenSourceLicensesView: View {
  var body: some View {
    List(OpenSourceNotice.all) { notice in
      NavigationLink {
        ScrollView {
          VStack(alignment: .leading, spacing: MemoraSpacing.lg) {
            Text(notice.name).font(.title2.bold())
            Text("\(notice.version) · \(notice.license)").font(.subheadline)
            Text(notice.copyright).font(.footnote)
            if let url = URL(string: notice.url) { Link("配布元を開く", destination: url) }
            Text(notice.text).font(.footnote).textSelection(.enabled)
          }
          .frame(maxWidth: MemoraSpacing.readingWidth, alignment: .leading)
          .padding(MemoraSpacing.screen)
          .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle(notice.name)
        .navigationBarTitleDisplayMode(.inline)
      } label: {
        VStack(alignment: .leading, spacing: 4) {
          Text(notice.name)
          Text("\(notice.version) · \(notice.license)").font(.caption).foregroundStyle(.secondary)
        }
        .frame(minHeight: 44)
      }
    }
    .navigationTitle("オープンソースライセンス")
    .navigationBarTitleDisplayMode(.inline)
    .accessibilityIdentifier("settings.openSourceLicenses")
  }
}
