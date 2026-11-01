import SwiftUI

struct ProjectPDFView: View {
  @Environment(MemoraModel.self) private var model
  var sourceID: UUID
  var page: Int = 1

  var body: some View {
    if let source = model.source(id: sourceID), source.kind == .pdf,
       let name = source.localFileReference, let url = ProjectSourceFiles.resolve(name) {
      LocalSourcePDFView(url: url, page: page)
      .navigationTitle(source.title).navigationBarTitleDisplayMode(.inline)
      .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: model.bottomContentClearance) }
    } else {
      ContentUnavailableView("PDFが見つかりません", icon: .docQuestionmark)
    }
  }
}
