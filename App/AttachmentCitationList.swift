import SwiftUI

struct AttachmentCitationList: View {
  @Environment(MemoraModel.self) private var model
  var citations: [AIAttachmentCitation]
  @State private var workspaceGeneration: UUID?

  var body: some View {
    let locations = citations.filter(\.isValid).reduce(into: [AIAttachmentCitation]()) { result, citation in
      if !result.contains(where: { $0.number == citation.number && $0.file.id == citation.file.id &&
        $0.page == citation.page && $0.time == citation.time && $0.excerpt == citation.excerpt }) {
        result.append(citation)
      }
    }
    Group {
      if model.currentTeamID == nil, !model.isRestoring,
         workspaceGeneration == nil || workspaceGeneration == model.aiWorkspaceGeneration {
        ForEach(Array(locations.enumerated()), id: \.offset) { _, citation in
          if resolvedFile(citation) != nil {
            NavigationLink {
              AttachmentCitationDestination(citation: citation, workspaceGeneration: workspaceGeneration ?? model.aiWorkspaceGeneration)
            } label: {
              Label(title(citation), icon: .docText)
                .font(.footnote).multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .tint(MemoraPalette.textPrimary)
            .accessibilityHint("引用した原文を開きます")
          } else {
            Label(title(citation) + " · 資料を開けません", icon: .docQuestionmark)
              .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.leading)
              .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
          }
        }
      }
    }
    .onAppear { if workspaceGeneration == nil { workspaceGeneration = model.aiWorkspaceGeneration } }
  }

  private func resolvedFile(_ citation: AIAttachmentCitation) -> AIAttachment.File? {
    citation.file.resolve()?.files.first(where: { $0.id == citation.file.id })
  }

  private func title(_ citation: AIAttachmentCitation) -> String {
    let location: String
    if let page = citation.page { location = " · ページ\(page)" }
    else if let time = ProjectCitationLocation.playbackTime(citation.time) { location = " · \(MemoraFormat.duration(time))" }
    else { location = "" }
    return citation.marker + " " + citation.file.name + location
  }
}

private struct AttachmentCitationDestination: View {
  @Environment(MemoraModel.self) private var model
  var citation: AIAttachmentCitation
  var workspaceGeneration: UUID

  var body: some View {
    Group {
      if model.currentTeamID == nil, !model.isRestoring, model.aiWorkspaceGeneration == workspaceGeneration, citation.isValid,
         let file = citation.file.resolve()?.files.first(where: { $0.id == citation.file.id }) {
        let kind = SourceIntake.kind(for: file.url)
        if kind == .pdf {
          LocalSourcePDFView(url: file.url, page: citation.page ?? 1)
            .navigationTitle(file.name).navigationBarTitleDisplayMode(.inline)
        } else if kind == .audio || kind == .video {
          LocalSourceMediaPlayerView(url: file.url, title: file.name, start: citation.time)
        } else {
          ConversationAttachmentView(file: file, initialExcerpt: citation.excerpt)
        }
      } else {
        ContentUnavailableView("資料を開けません", icon: .docQuestionmark,
          description: Text("会話から資料を開き直すか、元のファイルを追加してください。"))
      }
    }
  }
}
