import SwiftUI

struct SourceCitationList: View {
  @Environment(MemoraModel.self) private var model
  var citations: [ProjectCitation]
  var scope: AIQueryScope? = nil
  @State private var viewingPhoto: ProjectPhoto?
  @State private var photoUnavailable = false

  var body: some View {
    let locations = citations.reduce(into: [ProjectCitation]()) { result, citation in
      if !result.contains(where: {
        $0.target == citation.target && $0.page == citation.page && $0.time == citation.time && $0.photo == citation.photo
      }) {
        result.append(citation)
      }
    }
    let photos = locations.filter { $0.photo != nil }
    if model.currentTeamID == nil {
      ForEach(locations) { citation in
        if case .meeting(let id) = citation.target, let number = photos.firstIndex(of: citation) {
          Button {
            openPhoto(citation, recordID: id)
          } label: {
            Label("写真\(number + 1) · \(citation.title)", icon: .photo)
              .font(.footnote).multilineTextAlignment(.leading)
              .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
          }
          .tint(MemoraPalette.textPrimary)
          .accessibilityHint("引用した元の写真を開きます")
        } else if case .source(let id) = citation.target, let source = model.source(id: id) {
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
      .sheet(item: $viewingPhoto) { ProjectPhotoViewer(photo: $0) }
      .alert("元の写真が見つかりません", isPresented: $photoUnavailable) { Button("閉じる", role: .cancel) {} }
    }
  }

  private func openPhoto(_ citation: ProjectCitation, recordID: UUID) {
    guard let record = model.meeting(id: recordID),
          scope?.includes(recordID: recordID, projectID: record.spaceID) != false,
          let entry = model.currentPhotoEvidence(citation) else {
      photoUnavailable = true
      return
    }
    viewingPhoto = ProjectPhoto(name: entry.name, date: record.createdAt, recordID: recordID, recordTitle: record.displayTitle)
  }

  private func location(_ citation: ProjectCitation) -> String {
    if let page = citation.page { return " · ページ\(page)" }
    if let time = ProjectCitationLocation.playbackTime(citation.time) { return " · \(MemoraFormat.duration(time))" }
    return ""
  }
}
