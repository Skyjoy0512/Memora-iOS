import SwiftUI
import UniformTypeIdentifiers

struct CaptureHeroView: View {
  @Environment(MemoraModel.self) private var model
  @State private var isFileImporterPresented = false
  @State private var recordFeedback = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      VStack(alignment: .leading, spacing: 6) {
        Text("会話を、使える知識へ")
          .font(.title2.bold())
          .foregroundStyle(.white)
        Text("録音を止めたら、整理はMemoraに任せてください。")
          .font(.subheadline)
          .foregroundStyle(.white.opacity(0.76))
      }

      Button {
        recordFeedback += 1
        Task {
          await model.startCapture()
        }
      } label: {
        HStack(spacing: 12) {
          Image(systemName: "waveform")
            .font(.title3.weight(.semibold))
            .frame(width: 44, height: 44)
            .foregroundStyle(.indigo)
            .background(.white, in: Circle())

          VStack(alignment: .leading, spacing: 2) {
            Text("録音を始める")
              .font(.headline)
            Text("1タップで開始")
              .font(.caption)
              .foregroundStyle(.white.opacity(0.72))
          }

          Spacer()

          Image(systemName: "chevron.right")
            .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(.white)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      HStack {
        Label("端末に保存", systemImage: "lock.fill")
          .font(.caption)
          .foregroundStyle(.white.opacity(0.72))

        Spacer()

        Button("音声を読み込む", systemImage: "square.and.arrow.down") {
          isFileImporterPresented = true
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.white)
      }
    }
    .padding(20)
    .background(.indigo, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    .sensoryFeedback(.impact(weight: .medium), trigger: recordFeedback)
    .fileImporter(
      isPresented: $isFileImporterPresented,
      allowedContentTypes: [.audio],
      allowsMultipleSelection: false
    ) { result in
      switch result {
      case .success(let urls):
        guard let url = urls.first else { return }
        Task {
          await model.importAudio(from: url)
        }
      case .failure:
        model.importErrorMessage = "ファイルを選択できませんでした。もう一度お試しください。"
      }
    }
  }
}
