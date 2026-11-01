import SwiftUI

struct SourceMediaPlayerView: View {
  @Environment(MemoraModel.self) private var model
  var sourceID: UUID
  var start: TimeInterval?

  var body: some View {
    if let source = model.source(id: sourceID), let name = source.localFileReference,
       let url = ProjectSourceFiles.resolve(name) {
      LocalSourceMediaPlayerView(url: url, title: source.title, start: start)
      .navigationTitle(source.title).navigationBarTitleDisplayMode(.inline)
    } else { ContentUnavailableView("ファイルが見つかりません", icon: .docQuestionmark) }
  }
}
