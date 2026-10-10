import SwiftUI

struct SettingsNotesView: View {
  var body: some View {
    List {
      Section("アカウント") {
        Text("同期とアカウントはまだ接続されていません。録音と整理は、このiPhoneの中で使えます。")
      }
      Section("プラン") {
        Text("購入はまだ接続されていません。プランはこの端末の設定として保存します。チーム機能はチームプランか法人ライセンスで利用できます。")
      }
      Section("表示") {
        Text("ダークモードをオフにすると、iPhoneの外観の設定に合わせます。")
      }
      Section("処理") {
        Text("通常は変更不要です。端末やOSに合う方法をMemoraが選びます。")
      }
      Section("Face IDでロック") {
        Text("アプリを開いたときと、5分以上離れたあとに戻ったときに解除を求めます。録音中はロックしません。")
      }
      Section("サポート") {
        Text("公開時に実際の窓口とプライバシーポリシーのURLを登録します。それまでは準備中と表示し、存在しないリンクは開けません。")
      }
    }
    .navigationTitle("設定について")
    .memoraBackButton()
  }
}
