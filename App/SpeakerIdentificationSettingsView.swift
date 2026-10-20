import SwiftUI

struct SpeakerIdentificationSettingsView: View {
  @Environment(MemoraModel.self) private var model
  @State private var isInstalling = false
  @State private var completedFiles = 0
  @State private var totalFiles = 25
  @State private var errorMessage: String?
  @State private var downloadTask: Task<Void, Never>?
  @State private var confirmsDownload = false
  @State private var isProbing = false
  @State private var probeResult: String?

  var body: some View {
    @Bindable var model = model
    MemoraForm {
      Section("端末内の音声モデル") {
        Label(SpeakerModelAssets.isInstalled ? "モデルを保存済み" : "モデル未ダウンロード", icon: .waveform)
        Text("FluidAudio / Community-1。声の登録と録音後の話者分離に同じモデルを使います。音声や特徴量は外部に送信しません。")
          .foregroundStyle(.secondary)
        Text("初回は約22MBの通信が必要です。空き容量に余裕がある状態で、Wi-Fiでの取得をおすすめします。")
          .font(.footnote).foregroundStyle(.secondary)
        if isInstalling {
          ProgressView("取得・検証中（\(completedFiles)/\(totalFiles)）", value: Double(completedFiles), total: Double(totalFiles))
          Button("ダウンロードを中止", role: .cancel) { downloadTask?.cancel() }
        } else {
          Button(SpeakerModelAssets.isInstalled ? "モデルを検証・再取得" : "モデルをダウンロード", icon: .arrowDownDoc) {
            confirmsDownload = true
          }
        }
        if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.secondary) }
        #if DEBUG
        if SpeakerModelAssets.isInstalled {
          Button(isProbing ? "モデル動作チェック中…" : "モデル動作チェック（無音）") {
            isProbing = true
            Task {
              probeResult = await SpeakerModelProbe.run()
              isProbing = false
            }
          }
          .disabled(isProbing || isInstalling)
          if let probeResult { Text(probeResult).font(.footnote).foregroundStyle(.secondary) }
        }
        #endif
      }
      Section("利用方法") {
        Toggle("文字起こし後に話者を解析", isOn: $model.automaticallyAnalyzesSpeakers)
        Text("初期状態はオフです。オンにすると、保存済みのモデルで新しい文字起こしを端末内解析します。モデルは自動取得せず、解析できなくても原音声・原文は保持します。長い録音は処理時間・電池消費が増えます。")
          .font(.footnote).foregroundStyle(.secondary)
        NavigationLink { VoiceProfileView() } label: { Label("自分の声を登録", icon: .personWave2) }
        Text("記録の文字起こし画面で「話者を端末内で解析」を押してください。既存の文字起こしを再実行せずに解析します。")
        Text("発言の開始・終了時刻がある文字起こしだけに自動で対応付けます。重なりや不十分な時間情報は未確定のまま残します。")
          .foregroundStyle(.secondary)
      }
      Section("本人判定について") {
        Text("声の特徴量の登録・照合計算は利用できます。『自分』の自動確定は実機での判定基準の検証待ちです。匿名の話者名を原音声で確認し、手動で変更してください。")
        Text("類似度は本人である確率ではありません。認証用途には使いません。")
          .foregroundStyle(.secondary)
      }
      Section("モデルの利用条件") {
        Text("pyannote・WeSpeaker・BUT Speech@FIT・Fluid InferenceによるCommunity-1のCore ML変換モデル（変更あり）。モデルは対象ファイルに限りCC BY 4.0、SDKはApache 2.0です。")
          .font(.footnote)
        Link("モデルの出典・ライセンス", destination: URL(string: "https://huggingface.co/FluidInference/speaker-diarization-coreml/blob/df2625ac79a7ac6b65ad868fee6d80f320da4232/NOTICE.md")!)
        Link("CC BY 4.0", destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
        Link("FluidAudioのライセンス", destination: URL(string: "https://github.com/FluidInference/FluidAudio/blob/v0.17.7/LICENSE")!)
      }
    }
    .navigationTitle("話者識別")
    .memoraBackButton()
    .confirmationDialog("音声モデルをダウンロードしますか？", isPresented: $confirmsDownload) {
      Button("約22MBをダウンロード") { install() }
    } message: {
      Text("モデル取得のためHugging Faceへ接続します。録音や声の特徴量は送信しません。")
    }
    .onDisappear { downloadTask?.cancel() }
  }

  private func install() {
    isInstalling = true
    completedFiles = 0
    errorMessage = nil
    downloadTask = Task {
      defer { isInstalling = false }
      do {
        try await SpeakerModelAssets.shared.install { completed, total in
          await MainActor.run {
            completedFiles = completed
            totalFiles = total
          }
        }
      } catch is CancellationError {
        errorMessage = "取得を中断しました。次回は検証済みのファイルを再利用します。"
      } catch {
        errorMessage = "モデルを準備できませんでした。\(error.localizedDescription)"
      }
    }
  }
}
