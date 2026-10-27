import SwiftUI

struct PresentationDiagramFields: View {
  @Binding var slide: DocumentSlide

  var body: some View {
    if let diagram = slide.composition?.diagram {
      Section("図の項目") {
        ForEach(diagram.nodes, id: \.id) { node in
          if let index = diagram.nodes.firstIndex(where: { $0.id == node.id }) {
            TextField("項目", text: Binding(get: { slide.composition?.diagram?.nodes[index].label ?? "" },
              set: { slide.composition?.diagram?.nodes[index].label = $0 }), axis: .vertical)
          }
        }
      }
      Section("接続") {
        ForEach(diagram.edges.indices, id: \.self) { index in
          VStack(alignment: .leading) {
            Picker("接続元", selection: edgeValue(index, from: true)) {
              ForEach(diagram.nodes) { Text($0.label).tag($0.id) }
            }
            Picker("接続先", selection: edgeValue(index, from: false)) {
              ForEach(diagram.nodes) { Text($0.label).tag($0.id) }
            }
          }
        }
      }
    }
  }

  private func edgeValue(_ index: Int, from: Bool) -> Binding<String> {
    Binding(get: {
      guard let edges = slide.composition?.diagram?.edges, edges.indices.contains(index) else { return "" }
      return from ? edges[index].from : edges[index].to
    }, set: {
      guard slide.composition?.diagram?.edges.indices.contains(index) == true else { return }
      if from { slide.composition?.diagram?.edges[index].from = $0 } else { slide.composition?.diagram?.edges[index].to = $0 }
    })
  }
}
