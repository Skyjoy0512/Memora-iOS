import SwiftUI

struct ContentView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.openURL) private var openURL
  @AppStorage("memora.prefersDarkAppearance") private var prefersDarkAppearance = false

  var body: some View {
    @Bindable var model = model

    Group {
      if model.hasCompletedOnboarding {
        RootTabView()
          .transition(.opacity.combined(with: .scale(scale: 0.97)))
      } else {
        OnboardingView {
          model.completeOnboarding()
          Task {
            await model.startCapture()
          }
        } showSample: {
          model.completeOnboarding()
        } signIn: {
          model.completeOnboarding()
          model.isAuthPresented = true
        }
        .transition(.opacity)
      }
    }
    .animation(reduceMotion ? nil : MemoraMotion.screen, value: model.hasCompletedOnboarding)
    .sheet(isPresented: $model.isCapturePresented, onDismiss: {
      model.completeCaptureDismissal()
    }) {
      CaptureSessionView()
    }
    .sheet(isPresented: $model.isAuthPresented) {
      AuthView()
    }
    .sheet(isPresented: $model.isPaywallPresented) {
      PaywallView()
    }
    .overlay {
      if model.isImporting {
        ImportProgressOverlay(progress: model.importProgress)
          .transition(.opacity)
      }
    }
    .animation(reduceMotion ? nil : MemoraMotion.control, value: model.isImporting)
    .preferredColorScheme(prefersDarkAppearance ? .dark : nil)
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
