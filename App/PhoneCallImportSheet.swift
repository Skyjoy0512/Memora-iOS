import SwiftUI
import UniformTypeIdentifiers

/// Turns a phone call into a call memo. iOS gives no app the audio of a call,
/// so this starts from iPhone's own call recording: its audio file, or the
/// transcript it already wrote in Notes.
struct PhoneCallImportSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var isFileImporterPresented = false
  @State private var isPastingTranscript = false

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Label {
            Text("iPhoneの通話録音から、用件・約束・次にやることをまとめた通話メモを作ります。")
          } icon: {
            Image(icon: .phone)
              .foregroundStyle(.tint)
          }
          .font(.subheadline)
        }

        Section("1. 通話を録音する") {
          step(1, "通話中に、画面左上の録音ボタンをタップします。相手にも録音していることが伝わります。")
          step(2, "通話が終わると、録音と文字起こしが「メモ」Appに保存されます。")
        }

        Section {
          Button {
            isFileImporterPresented = true
          } label: {
            Label("録音ファイルを選ぶ", icon: .waveform)
          }
          Button {
            isPastingTranscript = true
          } label: {
            Label("文字起こしを貼り付ける", icon: .docText)
          }
        } header: {
          Text("2. Memoraに取り込む")
        } footer: {
          Text("「メモ」Appで録音をファイルに保存して選ぶか、メモの文字起こしをコピーして貼り付けてください。取り込むと、文字起こしと通話メモの作成まで自動で進みます。")
        }

        Section {
          Text("通話録音はiOS 18.1以降の、対応する国と地域で使えます。ほかのアプリは通話の音声を直接受け取れないため、この方法で取り込みます。")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("通話を議事録にする")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("閉じる", icon: .xmark) { dismiss() }
        }
      }
      .navigationDestination(isPresented: $isPastingTranscript) {
        CallTranscriptPasteView {
          dismiss()
        }
      }
      .fileImporter(
        isPresented: $isFileImporterPresented,
        allowedContentTypes: [.audio],
        allowsMultipleSelection: false
      ) { result in
        guard case .success(let urls) = result, let url = urls.first else { return }
        dismiss()
        Task {
          await model.importAudio(from: url, source: .phoneCall)
        }
      }
    }
  }

  private func step(_ number: Int, _ text: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text("\(number)")
        .font(.subheadline.weight(.semibold).monospacedDigit())
        .foregroundStyle(.tint)
      Text(text)
        .font(.subheadline)
    }
  }
}
