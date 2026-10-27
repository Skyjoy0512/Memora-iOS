import SwiftUI

#if DEBUG
struct PresentationCatalogView: View {
  var body: some View {
    List {
      NavigationLink("資料計画・部分修正の表示検証") { PresentationEditingExampleView() }
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
