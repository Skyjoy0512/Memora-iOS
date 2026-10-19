import AppIntents
import SwiftUI

@main
struct MemoraApp: App {
  @UIApplicationDelegateAdaptor(MemoraAppDelegate.self) private var appDelegate

  init() {
    let model = MemoraAppRuntime.shared.model
    AppDependencyManager.shared.add(dependency: model)
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .font(MemoraTypography.body)
        .tint(MemoraPalette.action)
        .background { InteractionFeedbackView() }
        .environment(appDelegate.model)
        .onAppear {
          #if DEBUG
          SelfChecks.run()
          #endif
        }
        .dismissKeyboardOnOutsideTap()
        .onOpenURL { url in
          Task {
            await appDelegate.model.handle(url)
          }
        }
    }
  }
}
