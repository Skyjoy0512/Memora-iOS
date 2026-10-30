import SwiftUI

#if DEBUG
/// Isolated fictional content; this screen never writes a document or calls an AI.
struct PresentationEditingExampleView: View {
  @State private var document: MemoraDocument
  @State private var editingRequest: PresentationEditRequest?

  init() {
    var slides = [PresentationExample.slide(.b01), PresentationExample.slide(.m03), PresentationExample.slide(.m34)]
    slides[0].title = ""
    let plan = PresentationPlan(purpose: "架空の表示検証", audience: "検証担当", decision: "表示と操作を確認",
      assumptions: ["架空データであり、実際の業績ではない"], storyline: slides.map {
        .init(slideID: $0.id, claim: $0.title, evidence: ["ローカルfixture"], unconfirmed: ["実機での確認"])
      })
    _document = State(initialValue: MemoraDocument(title: "架空の編集検証・保存しません", kind: .slides,
      slides: slides, presentationPlan: plan))
  }

  var body: some View {
    List {
      Section("品質と修正導線（先頭に未入力のタイトルを含む架空例）") {
        PresentationQualityView(document: document) { id in
          editingRequest = PresentationEditRequest(document: document, initialSlideID: id)
        }
      }
      Section {
        if let plan = Binding($document.presentationPlan) {
          NavigationLink("目的と構成") { PresentationPlanFields(plan: plan, slides: document.slides) }
        }
        Button("スライド編集を表示") { editingRequest = PresentationEditRequest(document: document) }
        NavigationLink("部分修正の入力を表示") {
          PresentationRevisionView(draft: $document, original: document)
        }
        NavigationLink("変更前後の比較を表示") {
          Form {
            var revised = document.slides[1]; let _ = revised.title = "指標を比較し、次の確認へ"
            PresentationRevisionComparison(revision: .init(originals: [document.slides[1]], replacements: [revised]))
          }
          .navigationTitle("架空の修正案")
          .navigationBarTitleDisplayMode(.inline)
        }
      } footer: {
        Text("保存済みデータは変更しません。部分修正の生成は、保存済み資料でないため権限検査で止まります。比較画面も固定の架空例です。")
      }
    }
    .navigationTitle("資料計画・部分修正の表示検証")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(item: $editingRequest) { request in
      PresentationEditorView(document: request.document, initialSlideID: request.initialSlideID)
    }
  }
}
#endif
