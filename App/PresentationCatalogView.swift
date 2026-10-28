import SwiftUI

#if DEBUG
struct PresentationCatalogView: View {
  var body: some View {
    List {
      NavigationLink("資料計画・部分修正の表示検証") { PresentationEditingExampleView() }
      NavigationLink("企業書式の計測を表示（架空PPTX）") { CompanyPresentationExampleView() }
      NavigationLink("会社PPTXの再出力（表示の確認）") { CompanyPresentationReexportExampleView() }
      NavigationLink("会社書式の追加ページ（表示の確認）") { CompanyPresentationPreviewExampleView() }
      ForEach(SlideArchetype.allCases) { layout in
        NavigationLink {
          PresentationSlideEditorHost(layout: layout)
        } label: {
          Text("\(layout.rawValue) \(layout.title)")
            .frame(minHeight: 44)
        }
      }
    }
    .navigationTitle("65レイアウトの表示検証")
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct PresentationSlideEditorHost: View {
  @State private var slide: DocumentSlide
  init(layout: SlideArchetype) { _slide = State(initialValue: PresentationExample.slide(layout)) }
  var body: some View { PresentationSlideEditor(slide: $slide) }
}
#endif
