import SwiftUI

@main
struct MemoraApp: App {
  @State private var model = MemoraModel()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(model)
        .tint(.indigo)
        .onOpenURL { url in
          Task {
            await model.handle(url)
          }
        }
    }
  }
}
