import SwiftUI

@main
struct MemoraApp: App {
  @UIApplicationDelegateAdaptor(MemoraAppDelegate.self) private var appDelegate
  @State private var model = MemoraModel()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(model)
        .onAppear {
          #if DEBUG
          SelfChecks.run()
          #endif
        }
        .dismissKeyboardOnOutsideTap()
        .onOpenURL { url in
          Task {
            await model.handle(url)
          }
        }
    }
  }
}
