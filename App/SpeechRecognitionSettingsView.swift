import SwiftUI

struct SpeechRecognitionSettingsView: View {
  @AppStorage("memora.transcriptionEngine") private var engine = TranscriptionEngine.automatic
  @AppStorage("memora.transcriptionLanguage") private var language = RecognitionLanguage.japanese
  @AppStorage("memora.transcriptionProvider") private var provider = CloudProvider.openAI
  @State private var isKeySheetPresented = false

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
  }
}
