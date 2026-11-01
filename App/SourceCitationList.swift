import SwiftUI

struct SourceCitationList: View {
  @Environment(MemoraModel.self) private var model
  var citations: [ProjectCitation]

  var body: some View {
    if model.currentTeamID == nil {
      ForEach(citations) { citation in
        if case .source(let id) = citation.target, let source = model.source(id: id) {
          NavigationLink {
            if source.kind == .pdf, let page = citation.page {
              ProjectPDFView(sourceID: id, page: page)
            } else if source.kind == .audio || source.kind == .video {
              SourceMediaPlayerView(sourceID: id, start: citation.time)
            } else {
              ProjectSourceDetailView(sourceID: id, initialExcerpt: citation.excerpt)
            }
          } label: {
            Label(citation.title + location(citation), icon: .docText)
              .font(.footnote).multilineTextAlignment(.leading)
              .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
          }
          .tint(MemoraPalette.textPrimary)
          .accessibilityHint("引用した原文を開きます")
        }
      }
    }
  }

  private func location(_ citation: ProjectCitation) -> String {
    if let page = citation.page { return " · ページ\(page)" }
    if let time = ProjectCitationLocation.playbackTime(citation.time) { return " · \(MemoraFormat.duration(time))" }
    return ""
  }
}
