import Foundation

enum PresentationPlanningChecks {
  static func run() throws {
    let slides = [DocumentSlide(title: "結論", bullets: []), DocumentSlide(title: "根拠", bullets: ["確認済みの事実"])]
    let json = #"{"purpose":"経営判断","audience":"経営会議","decision":"次の調査範囲を決める","assumptions":["費用は未確認"],"storyline":[{"slide_number":1,"claim":"調査を先に行う","evidence":["会議・決定事項"],"unconfirmed":[]},{"slide_number":2,"claim":"費用の根拠が不足","evidence":[],"unconfirmed":["概算"]}]}"#
    let plan = try PresentationToolInput.plan(json, slides: slides)
    precondition(plan.isValid(for: slides) && plan.storyline.map(\.slideID) == slides.map(\.id))
    precondition(plan.reviewNotes(for: slides).contains { $0.contains("未確認事項") })
    let document = MemoraDocument(title: "計画", kind: .slides, slides: slides, presentationPlan: plan)
    let roundtrip = try JSONDecoder().decode(MemoraDocument.self, from: JSONEncoder().encode(document))
    precondition(roundtrip == document)
    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as! [String: Any]
    legacy.removeValue(forKey: "presentationPlan")
    let restored = try JSONDecoder().decode(MemoraDocument.self, from: JSONSerialization.data(withJSONObject: legacy))
    precondition(restored.presentationPlan == nil && restored.slides == slides)
    precondition(plan.reconciled(with: Array(slides.reversed())).storyline.map(\.slideID) == slides.reversed().map(\.id))
    precondition(plan.reconciled(with: [slides[1]]).storyline.map(\.slideID) == [slides[1].id])
    let edited = document.editing(title: "編集", body: "# 新しいスライド\n- 新しい要点")!
    precondition(edited.presentationPlan?.storyline.isEmpty == true && edited.contentRevision == 1)
    for bad in [json.replacingOccurrences(of: "\"slide_number\":2", with: "\"slide_number\":1"),
                json.replacingOccurrences(of: "\"slide_number\":2", with: "\"slide_number\":0"),
                json.replacingOccurrences(of: "\"slide_number\":2", with: "\"slide_number\":999"),
                json.replacingOccurrences(of: "\"purpose\":", with: "\"unknown\":true,\"purpose\":"),
                String(repeating: "x", count: 50_001)] {
      do { _ = try PresentationToolInput.plan(bad, slides: slides); preconditionFailure("Bad plan accepted") } catch {}
    }
    print("Presentation planning passed: legacy decode, source/unknown separation, bounded input, stable slide IDs, reorder/delete reconciliation and revision-safe outline editing")
  }
}
