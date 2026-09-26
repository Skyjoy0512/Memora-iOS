import SwiftUI

struct SpeechRecognitionSettingsView: View {
  @AppStorage("memora.transcriptionEngine") private var engine = TranscriptionEngine.automatic
  @AppStorage("memora.transcriptionLanguage") private var language = RecognitionLanguage.japanese
  @AppStorage("memora.transcriptionProvider") private var provider = CloudProvider.openAI
  @AppStorage("memora.liveTranscription") private var liveTranscription = true
  @State private var isKeySheetPresented = false
  @State private var availability = EngineAvailability.Status()

  var body: some View {
    Form {
      Section {
        Picker("方法", selection: $engine) {
          ForEach(TranscriptionEngine.allCases) { option in
            Text(option.label).tag(option)
          }
        }
        Text(engine.detail)
          .font(.footnote)
          .foregroundStyle(.secondary)
      } header: {
        Text("文字起こし方法")
      } footer: {
        Text("端末内を優先し、必要な時だけクラウドを使います。")
      }

      if engine.usesCloud {
        Section {
          Picker("プロバイダー", selection: $provider) {
            ForEach(CloudProvider.allCases.filter(\.supportsTranscription)) { option in
              Text(option.label).tag(option)
            }
          }
          Button("APIキーを設定", systemImage: "key") {
            isKeySheetPresented = true
          }
        } header: {
          Text("クラウド（BYOK）")
        } footer: {
          Text("キーはKeychainに保存し、設定画面にも再表示しません。")
        }
      }

      Section {
        Picker("主な言語", selection: $language) {
          ForEach(RecognitionLanguage.allCases) { option in
            Text(option.label).tag(option)
          }
        }
      } header: {
        Text("言語")
      } footer: {
        Text(language.detail)
      }

      Section {
        Toggle("録音中に文字起こしを表示", isOn: $liveTranscription)
      } header: {
        Text("録音中")
      } footer: {
        Text("iOS 26 以降の端末内エンジンで、録音中に発言を表示します。表示だけに使い、保存する文字起こしは録音後に音声から作成します。")
      }

      Section {
        LabeledContent("この設定での状態", value: availability.summary)
        if let message = availability.message {
          Text(message)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      } header: {
        Text("対応状況")
      } footer: {
        Text("対応言語・モデルの準備・キーの有無を、実行前にここで確認できます。")
      }
    }
    .navigationTitle("文字起こし")
    .memoraBackButton()
    .sheet(isPresented: $isKeySheetPresented) {
      APIKeySheet(provider: provider.label, account: "transcription.\(provider.rawValue)")
    }
    .onAppear {
      if !provider.supportsTranscription {
        provider = .openAI
      }
    }
    .task(id: "\(engine.rawValue)-\(language.rawValue)-\(provider.rawValue)") {
      availability = await EngineAvailability.transcription(engine, language: language, provider: provider)
    }
  }
}
