#if DEBUG
import SwiftUI

struct OmiPairingReviewView: View {
  @State private var presentedReview: Review?

  var body: some View {
    MemoraList {
      Section {
        Button("準備中") { review(.preparing) }
        Button("候補なしの検索") { review(.scanning) }
        Button("接続中") { review(.connecting("Omi（表示例）")) }
        Button("Bluetoothオフ") { review(.bluetoothOff) }
        Button("アクセス未許可") { review(.unauthorized) }
        Button("接続失敗") { review(.failed("電源を確認してから、接続し直してください。")) }
      } footer: {
        Text("架空の状態を使います。Bluetoothの検索や接続は行いません。")
      }
    }
    .navigationTitle("外部レコーダーの状態")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(item: $presentedReview) { review in
      OmiPairingView(manager: review.manager, isReview: true)
    }
  }

  private func review(_ state: OmiPairingManager.ConnectionState) {
    presentedReview = Review(manager: OmiPairingManager(reviewState: state))
  }

  private struct Review: Identifiable {
    let id = UUID()
    var manager: OmiPairingManager
  }
}
#endif
