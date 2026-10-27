import SwiftUI

#if DEBUG
/// Exercises the production parser on an in-memory package; no records or files are saved.
struct CompanyPresentationExampleView: View {
  @State private var profile: CompanyPresentationProfile?
  @State private var error: String?

  var body: some View {
    MemoraForm {
      Section {
        Text("架空のPPTXを端末内で計測する表示検証です。会社ファイルを読み込まず、資料も保存しません。")
          .font(.footnote).foregroundStyle(.secondary)
      }
      if let profile { CompanyPresentationProfileView(profile: profile) }
      else if let error { Section { Text(error) } }
      else { Section { Text("端末内で計測しています") } }
    }
    .navigationTitle("企業書式の計測・架空例").navigationBarTitleDisplayMode(.inline)
    .task {
      guard profile == nil else { return }
      do {
        profile = try await Task.detached(priority: .userInitiated) {
          let source = PPTXWriter.data(for: .init(title: "架空の書式", kind: .slides, slides: [.init(title: "架空の報告", bullets: ["表示検証のみ"]) ]))
          var archive = try OfficeArchiveReader(data: source), fixture = ZipArchive()
          let placeholder = "<p:sp><p:nvSpPr><p:cNvPr id='30' name='Title'/><p:cNvSpPr/><p:nvPr><p:ph type='title' idx='0'/></p:nvPr></p:nvSpPr><p:spPr>%FRAME%</p:spPr><p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr sz='2800'><a:ea typeface='Hiragino Sans'/></a:defRPr></a:pPr><a:endParaRPr/></a:p></p:txBody></p:sp>"
          for part in archive.partNames {
            let data = try archive.read(part)
            if part == "ppt/slideMasters/slideMaster1.xml" || part == "ppt/slideLayouts/slideLayout1.xml" {
              let frame = part.contains("slideMasters/") ? "<a:xfrm><a:off x='685800' y='355600'/><a:ext cx='10820400' cy='1016000'/></a:xfrm>" : ""
              fixture.add(part, text: String(decoding: data, as: UTF8.self).replacingOccurrences(of: "</p:spTree>", with: placeholder.replacingOccurrences(of: "%FRAME%", with: frame) + "</p:spTree>"))
            } else { fixture.add(part, data: data) }
          }
          guard let measured = try CompanyTemplateEngine.analyze(fixture.data(), format: .pptx).presentation else { throw OfficeArchiveReader.Failure.invalid }
          return measured
        }.value
      } catch { self.error = error.localizedDescription }
    }
  }
}
#endif
