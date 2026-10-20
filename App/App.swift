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
        // The interface speaks Japanese, so system-formatted dates and pickers
        // follow it rather than the device's display language.
        .environment(\.locale, Locale(identifier: "ja_JP"))
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
