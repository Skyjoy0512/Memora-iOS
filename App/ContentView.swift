import SwiftUI

struct ContentView: View {
  @AppStorage("hasSeenMemoraWelcome") private var hasSeenWelcome = false
  @Environment(MemoraModel.self) private var model
  @Environment(\.openURL) private var openURL

  var body: some View {
    @Bindable var model = model

    Group {
      if hasSeenWelcome {
        RootTabView()
      } else {
        OnboardingView {
          hasSeenWelcome = true
          Task {
            await model.startCapture()
          }
        } showSample: {
          hasSeenWelcome = true
        }
      }
    }
    .animation(.smooth, value: hasSeenWelcome)
    .fullScreenCover(isPresented: $model.isCapturePresented) {
      CaptureSessionView()
    }
    .sheet(isPresented: $model.isSettingsPresented) {
      SettingsView()
    }
    .overlay {
      if model.isImporting {
        ImportProgressOverlay(progress: model.importProgress)
      }
    }
    .alert("マイクへのアクセスが必要です", isPresented: $model.microphonePermissionDenied) {
      Button("設定を開く") {
        if let url = URL(string: UIApplication.openSettingsURLString) {
          openURL(url)
        }
      }
      Button("キャンセル", role: .cancel) {}
    } message: {
      Text("録音は許可した時だけ始まります。設定でマイクを許可すると、会話をこのiPhoneに保存できます。")
    }
    .alert("録音を開始できませんでした", isPresented: recordingErrorBinding) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(model.recordingErrorMessage ?? "もう一度お試しください。")
    }
    .alert("インポートできませんでした", isPresented: importErrorBinding) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(model.importErrorMessage ?? "別の音声ファイルをお試しください。")
    }
  }

  private var recordingErrorBinding: Binding<Bool> {
    Binding {
      model.recordingErrorMessage != nil
    } set: { isPresented in
      if !isPresented {
        model.recordingErrorMessage = nil
      }
    }
  }

  private var importErrorBinding: Binding<Bool> {
    Binding {
      model.importErrorMessage != nil
    } set: { isPresented in
      if !isPresented {
        model.importErrorMessage = nil
      }
    }
  }
}
