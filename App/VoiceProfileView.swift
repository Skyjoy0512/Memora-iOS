import SwiftUI

struct VoiceProfileView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.scenePhase) private var scenePhase
  @State private var enrollment = VoiceEnrollmentService()
  @State private var player = AudioPlayerService()
  @State private var isDeleteConfirmationPresented = false
  @State private var saveError: String?
  @State private var consentsToEmbedding = false
  @State private var keepsSample = false
  @State private var isGeneratingEmbedding = false
  @State private var registrationTask: Task<Void, Never>?

  var body: some View {
    Form {
      Section {
        Label(model.speakerProfile == nil ? "自分の声を登録" : "声の特徴量を登録済み", icon: .personWave2)
          .font(.headline)
        Text("声を登録すると、録音の中からあなたの発言を確認しやすくなります。静かな場所で、自分だけで20〜40秒を目安に自然な声で話してください。")
          .foregroundStyle(.secondary)
        if let profile = model.speakerProfile {
          LabeledContent("登録日", value: profile.createdAt.formatted(date: .abbreviated, time: .omitted))
          LabeledContent("発話を検出", value: "\(Int(profile.qualityMetadata.speechDuration))秒")
          Toggle("登録した声の照合を有効にする", isOn: Binding {
            model.speakerProfile?.isEnabled == true
          } set: { model.setSpeakerProfileEnabled($0) })
          .disabled(isGeneratingEmbedding || enrollment.isRecording || enrollment.isPreparing || model.isRestoring || model.isStoreProtected)
          if profile.embeddingModelVersion != SpeakerModelAssets.revision {
            Text("モデルが変わっています。再登録してください。")
          }
        } else if model.voiceProfile != nil {
          Text("以前の登録は音声サンプルのみです。特徴量を生成するには再登録してください。")
        } else if model.speakerProfileReference != nil {
          Text("声の特徴量を読み込めません。ロック解除後に開き直すか、この端末で再登録してください。")
        }
      } footer: {
        Text("声の特徴量はこの端末だけで生成・暗号化して保存します。自動で『自分』と確定する機能は実機検証待ちです。認証には使いません。")
      }

      if !SpeakerModelAssets.isInstalled {
        Section {
          NavigationLink { SpeakerIdentificationSettingsView() } label: { Label("音声モデルを準備", icon: .arrowDownDoc) }
        } footer: { Text("声の特徴量を生成する前に、音声モデルをダウンロードしてください。") }
      }
      Section("保存への同意") {
        Toggle("話者識別のため、声の特徴量をこの端末に保存することに同意する", isOn: $consentsToEmbedding)
        Toggle("登録に使った音声も残す", isOn: $keepsSample)
        Text("音声を残さない場合、特徴量の生成・保存後に登録用の音声を削除します。特徴量・登録用音声はバックアップやチーム共有の対象外です。")
          .font(.footnote).foregroundStyle(.secondary)
      }
      .disabled(isGeneratingEmbedding)

      Section("読み上げ例") {
        Text("これは私の声のサンプルです。今日は、これから取り組みたいことについて話します。会議では、相手の話を聞きながら、自分の考えも伝えていきたいです。日々の会話を振り返り、次の行動につなげたいと思います。")
          .lineSpacing(5)
          .textSelection(.enabled)
      }

      Section {
        if enrollment.isRecording {
          VoiceEnrollmentProgress(enrollment: enrollment)
          Button("録音を終了", icon: .stopFill) { enrollment.finish() }
        } else if isGeneratingEmbedding {
          ProgressView("発話・音質を確認し、声の特徴量を生成しています…")
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
            isGeneratingEmbedding = true
            saveError = nil
            let consentAt = Date.now
            let shouldKeepSample = keepsSample
            registrationTask = Task {
              defer { isGeneratingEmbedding = false }
              do {
                try await model.enrollCurrentSpeaker(fileURL: candidate, consentAt: consentAt, keepsSample: shouldKeepSample)
                enrollment.didSave()
                consentsToEmbedding = false
              } catch {
                saveError = "声の登録を完了できませんでした。\(error.localizedDescription)"
              }
            }
          }
          .disabled(!consentsToEmbedding || !SpeakerModelAssets.isInstalled || isGeneratingEmbedding || model.isRestoring || model.isStoreProtected)
          Button("サンプルを破棄", role: .destructive) {
            player.stop()
            enrollment.cancel()
          }
          .disabled(isGeneratingEmbedding)
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
        Text("40秒で自動停止します。無音・音割れ・複数話者を検出すると登録しません。騒音や本人判定の精度は実機検証が必要です。")
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
        }
      }
      if model.speakerProfileReference != nil || model.speakerProfile != nil || model.voiceProfile != nil || SpeakerProfileStore.hasStoredProfile {
        Section {
          Button("登録した声を削除", role: .destructive) { isDeleteConfirmationPresented = true }
            .disabled(isGeneratingEmbedding || enrollment.isRecording || enrollment.isPreparing || model.isRestoring || model.isStoreProtected)
        }
      }

      Section {
        Label("このiPhoneだけに保存", icon: .lockShield)
        Text("サンプルはAIや外部サービス、チームへ送信しません。Memoraの書き出しや端末のバックアップにも含めません。削除や再登録はいつでもできます。")
          .font(.footnote).foregroundStyle(.secondary)
      }
    }
    .navigationTitle("自分の声を登録")
    .memoraBackButton()
    .confirmationDialog("登録した声を削除しますか？", isPresented: $isDeleteConfirmationPresented, titleVisibility: .visible) {
      Button("削除", role: .destructive) {
        player.stop()
        let embeddingDeleted = model.removeSpeakerEmbedding()
        let sampleDeleted = model.voiceProfile == nil || model.removeVoiceProfile()
        if !embeddingDeleted || !sampleDeleted { saveError = "保存データの削除を完了できませんでした。保存状態を確認し、もう一度お試しください。" }
      }
    } message: {
      Text("声の特徴量・暗号化キー・登録用の音声を削除します。過去の録音や手動の話者名は変更しません。")
    }
    .onChange(of: scenePhase) { _, phase in
      if phase != .active {
        if enrollment.isRecording { enrollment.finish() }
        if phase == .background, enrollment.isPreparing { enrollment.cancel() }
        player.stop()
      }
    }
    .onDisappear {
      registrationTask?.cancel()
      player.stop()
      enrollment.close()
    }
    .task { model.reloadSpeakerProfile() }
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
