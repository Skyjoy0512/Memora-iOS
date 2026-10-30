import SwiftUI
import UIKit

#if DEBUG
struct PhotoEditingExampleView: View {
  @State private var isEditing = false
  @State private var edited: Data?
  private static let sample = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 480)).jpegData(withCompressionQuality: 0.9) { context in
    UIColor.systemTeal.setFill()
    context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
    UIColor.white.setFill()
    context.fill(CGRect(x: 80, y: 80, width: 200, height: 200))
    UIColor.systemOrange.setFill()
    context.fill(CGRect(x: 360, y: 200, width: 200, height: 200))
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text("生成した図形の検証画像です。記録や写真ライブラリへ保存しません。")
        Button("写真編集を開く") { isEditing = true }.buttonStyle(.bordered)
        if let data = edited, let image = UIImage(data: data) {
          Image(uiImage: image).resizable().scaledToFit().accessibilityLabel("編集結果")
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading).padding()
    }
    .navigationTitle("写真編集の表示検証")
    .sheet(isPresented: $isEditing) { PhotoEditorView(source: Self.sample) { edited = $0 } }
  }
}
#endif
