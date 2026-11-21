import SwiftUI

struct SettingsNotesView: View {
  var body: some View {
    MemoraForm {
      Section("アカウント") {
        Text("同期とアカウントはまだ接続されていません。録音と整理は、このiPhoneの中で使えます。")
      }
      Section("プラン") {
        Text("プランはこの端末の設定として保存します。アプリ内購入は準備中です。")
        Text("チームの作成には、サービスへの接続とチームプランまたは法人ライセンスが必要です。")
      }
      Section("表示") {
        Text("「表示と操作」の外観で「システムに合わせる」「ライト」「ダーク」を選べます。")
      }
      Section("録音と保存") {
        Text("ライブラリの＋から録音や音声の取り込みを始められます。録音は端末に保存し、ライブラリから開けます。")
        Text("機種変更に備えて、データ管理のバックアップから記録を書き出せます。")
      }
      Section("Face IDでロック") {
        Text("アプリを開いたときと、5分以上離れたあとに戻ったときに解除を求めます。録音中はロックしません。")
      }
      Section("データ") {
        NavigationLink("データの保存先と外部送信") { PrivacyStorageView() }
      }
    }
    .navigationTitle("ヘルプ")
    .memoraBackButton()
  }
}
