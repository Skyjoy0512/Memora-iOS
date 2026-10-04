import SwiftUI

/// The top of Ask AI: Memora's mark and name in the middle, a new chat on the
/// left, and the rest — history, search, what it looks across — behind ….
struct AskAIHeader: View {
  @Environment(MemoraModel.self) private var model
  var onNewChat: () -> Void
  var onHistory: () -> Void
  var onSearch: () -> Void

  var body: some View {
    ZStack {
      HStack {
        Button(action: onNewChat) {
          Image(icon: .squareAndPencil)
            .font(.body.weight(.medium))
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .memoraGlass(in: Circle(), interactive: true)
        .disabled(model.aiMessages.isEmpty)
        .accessibilityLabel("新しいチャット")

        Spacer()

        Menu {
          Button("履歴", icon: .clockArrowCirclepath, action: onHistory)
          Button("検索", icon: .magnifyingglass, action: onSearch)
          Picker("対象", selection: Binding(
            get: { model.aiScope },
            set: { model.changeAIScope($0) }
          )) {
            ForEach(AIChatScope.allCases) { scope in
              Label(scope.title, icon: scope.symbol).tag(scope)
            }
          }
          .pickerStyle(.menu)
        } label: {
          Image(icon: .ellipsis)
            .font(.body.weight(.semibold))
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .memoraGlass(in: Circle(), interactive: true)
        .accessibilityLabel("その他")
      }
      .padding(.horizontal, 18)
      .frame(maxHeight: .infinity, alignment: .top)

      VStack(spacing: -10) {
        Image(icon: .sparkle)
          .font(.title2.weight(.semibold))
          .foregroundStyle(.white)
          .frame(width: 56, height: 56)
          .background(
            LinearGradient(colors: [.accentColor, .accentColor.opacity(0.75)], startPoint: .top, endPoint: .bottom),
            in: Circle()
          )
        Text("Memora")
          .font(.headline)
          .padding(.horizontal, 16)
          .padding(.vertical, 6)
          .memoraGlass(in: Capsule())
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Memora")
      .accessibilityAddTraits(.isHeader)
    }
    .frame(height: 96)
    .padding(.top, 4)
  }
}
