import SwiftUI

#if DEBUG
/// Uses production pagination without touching the person's records or AI.
struct SlideLayoutExampleView: View {
  var body: some View {
    ScrollView {
      DocumentSlidesView(document: Self.document)
        .frame(maxWidth: MemoraSpacing.readingWidth)
        .padding(MemoraSpacing.screen)
        .frame(maxWidth: .infinity)
    }
    .background(MemoraPalette.background)
    .navigationTitle("スライドの組版")
    .navigationBarTitleDisplayMode(.inline)
    .memoraBackButton()
  }

  private static let document = MemoraDocument(title: "スライドの表示検証", kind: .slides, slides: [
    DocumentSlide(title: "会議のあとを、\n次の仕事へ。", bullets: [], notes: "架空データによる表示確認です。AIや外部サービスは使いません。"),
    DocumentSlide(title: "次回までに確認すること", bullets: [
      "公開日は決めず、録音開始までの操作を先に確認する。",
      "予算と担当者は会議で決まっていないため、未定として残す。",
      "条件と留保を含む原文を保持する。"], notes: "結論だけでなく、決定していない点も確認します。"),
    DocumentSlide(title: "長い本文の続き", bullets: [
      String(repeating: "これは組版の検証文です。長い要点も小さな文字へ縮めず、元の順序を保って次ページに続けます。", count: 12),
      "最後の要点も省略しません。"])
  ])
}
#endif
