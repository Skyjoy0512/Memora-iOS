import SwiftUI

@main
struct MemoraApp: App {
  @UIApplicationDelegateAdaptor(MemoraAppDelegate.self) private var appDelegate

  var body: some Scene {
    WindowGroup {
      ContentView()
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
