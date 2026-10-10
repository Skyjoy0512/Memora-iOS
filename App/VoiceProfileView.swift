import SwiftUI

struct VoiceProfileView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.scenePhase) private var scenePhase
  @State private var enrollment = VoiceEnrollmentService()
  @State private var player = AudioPlayerService()
  @State private var isDeleteConfirmationPresented = false
  @State private var saveError: String?

  var body: some View {
    Form {
      Section {
        Label(model.voiceProfile == nil ? "音声サンプルを登録" : "サンプル登録済み", icon: .personWave2)
          .font(.headline)
        Text("静かな場所で、iPhoneに向かって普段の声で10〜30秒話してください。")
          .foregroundStyle(.secondary)
        if let profile = model.voiceProfile {
          LabeledContent("登録日", value: profile.registeredAt.formatted(date: .abbreviated, time: .omitted))
          LabeledContent("長さ", value: "\(Int(profile.duration))秒")
        }
      } footer: {
        Text("この登録は音声サンプルの保存です。録音から自分の発言を自動で識別する機能は、まだ利用できません。")
      }

      Section("読み上げ例") {
        Text("これは私の声のサンプルです。今日は、これから取り組みたいことについて話します。会議では、相手の話を聞きながら、自分の考えも伝えていきたいです。日々の会話を振り返り、次の行動につなげたいと思います。")
          .lineSpacing(5)
          .textSelection(.enabled)
      }

      Section {
        if enrollment.isRecording {
          LabeledContent("録音中", value: "\(Int(enrollment.duration)) / 30秒")
            .monospacedDigit()
            .accessibilityValue("\(Int(enrollment.duration))秒録音しました")
          ProgressView(value: enrollment.level)
            .accessibilityLabel("マイクの音量")
          Button("録音を終了", icon: .stopFill) { enrollment.finish() }
        } else if enrollment.isPreparing {
          ProgressView("マイクを準備しています…")
        } else {
          Button(enrollment.candidateURL != nil || model.voiceProfile != nil ? "もう一度録音" : "録音を開始", icon: .mic) {
            player.stop()
            saveError = nil
            Task { await enrollment.start() }
          }
          .disabled(model.isRecording || model.isPreparingCapture || model.isRestoring || model.isStoreProtected)
        }

        if let candidate = enrollment.candidateURL, !enrollment.isRecording, !enrollment.isPreparing {
          Button(player.isPlaying ? "確認を停止" : "サンプルを確認", icon: player.isPlaying ? .stopFill : .playFill) {
            play(candidate)
          }
          Button("この声を登録", icon: .checkmark) {
            player.stop()
            if model.saveVoiceProfile(fileURL: candidate, duration: enrollment.duration) {
              enrollment.didSave()
              saveError = nil
            } else {
              saveError = "音声サンプルを登録できませんでした。空き容量や保存状態を確認して、もう一度お試しください。"
            }
          }
          .disabled(model.isRestoring || model.isStoreProtected)
          Button("サンプルを破棄", role: .destructive) {
            player.stop()
            enrollment.cancel()
          }
        }

        if let reason = enrollment.errorMessage ?? saveError ?? player.errorMessage {
          Text(reason).font(.footnote).foregroundStyle(.secondary)
        }
        if model.isRecording || model.isPreparingCapture {
          Text("会話の録音を終えてから声を登録してください。")
            .font(.footnote).foregroundStyle(.secondary)
        }
      } header: {
        Text("声の登録")
      } footer: {
        Text("30秒で自動停止します。「この声を登録」を押すまで、以前のサンプルは置き換えません。")
      }

      if let profile = model.voiceProfile {
        Section("登録した声") {
          if let url = VoiceProfileFiles.resolve(profile.fileName), FileManager.default.fileExists(atPath: url.path) {
            Button(player.isPlaying ? "再生を停止" : "登録した声を再生", icon: player.isPlaying ? .stopFill : .playFill) {
              play(url)
            }
            .disabled(enrollment.isRecording || enrollment.isPreparing)
          } else {
            Text("音声ファイルが見つかりません。もう一度録音して登録してください。")
              .foregroundStyle(.secondary)
          }
          Button("登録した声を削除", role: .destructive) { isDeleteConfirmationPresented = true }
            .disabled(enrollment.isRecording || enrollment.isPreparing || model.isRestoring || model.isStoreProtected)
        }
      }

      Section {
        Label("このiPhoneだけに保存", icon: .lockShield)
        Text("サンプルはAIや外部サービス、チームへ送信しません。Memoraの書き出しや端末のバックアップにも含めません。削除や再登録はいつでもできます。")
          .font(.footnote).foregroundStyle(.secondary)
      }
    }
    .navigationTitle("自分の声")
    .memoraBackButton()
    .confirmationDialog("登録した声を削除しますか？", isPresented: $isDeleteConfirmationPresented, titleVisibility: .visible) {
      Button("削除", role: .destructive) {
        player.stop()
        if !model.removeVoiceProfile() { saveError = "削除できませんでした。もう一度お試しください。" }
      }
    } message: {
      Text("音声サンプルをこのiPhoneから削除します。")
    }
    .onChange(of: scenePhase) { _, phase in
      if phase != .active {
        if enrollment.isRecording { enrollment.finish() }
        if phase == .background, enrollment.isPreparing { enrollment.cancel() }
        player.stop()
      }
    }
    .onDisappear {
      player.stop()
      enrollment.close()
    }
  }

  private func play(_ url: URL) {
    if player.isPlaying {
      player.stop()
    } else {
      player.load(url, title: "自分の声のサンプル")
      player.play()
    }
  }
}
