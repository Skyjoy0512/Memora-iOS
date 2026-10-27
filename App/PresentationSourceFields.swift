import SwiftUI

struct PresentationSourceFields: View {
  @Binding var slide: DocumentSlide

  var body: some View {
    if let sources = slide.composition?.sources {
      ForEach(sources.indices, id: \.self) { index in
        TextField("出典名", text: sourceValue(index, title: true), axis: .vertical)
        TextField("参照箇所・URL", text: sourceValue(index, title: false), axis: .vertical)
          .textInputAutocapitalization(.never).autocorrectionDisabled()
      }
    }
    Button("出典を追加") {
      if slide.composition?.sources == nil { slide.composition?.sources = [] }
      slide.composition?.sources?.append(.init(title: "", locator: ""))
    }
  }
  private func sourceValue(_ index: Int, title: Bool) -> Binding<String> {
    Binding(get: {
      guard let sources = slide.composition?.sources, sources.indices.contains(index) else { return "" }
      return title ? sources[index].title : sources[index].locator
    }, set: {
      guard slide.composition?.sources?.indices.contains(index) == true else { return }
      if title { slide.composition?.sources?[index].title = $0 } else { slide.composition?.sources?[index].locator = $0 }
    })
  }
}
