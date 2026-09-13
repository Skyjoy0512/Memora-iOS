import SwiftUI

struct RootTabView: View {
  @Environment(MemoraModel.self) private var model

  var body: some View {
    @Bindable var model = model

    TabView(selection: $model.selectedTab) {
      LibraryView()
        .tabItem {
          Label("会議", systemImage: "waveform")
        }
        .tag(RootTab.records)

      SearchView()
        .tabItem {
          Label("探す", systemImage: "magnifyingglass")
        }
        .tag(RootTab.search)

      TasksView()
        .tabItem {
          Label("タスク", systemImage: "checkmark.square")
        }
        .tag(RootTab.tasks)
    }
  }
}
