import SwiftUI

/// The top of Ask AI: Memora's mark and name in the middle, what it looks
/// across on the left, and history, search and a new chat on the right — the
/// new chat at the far edge, where it is easiest to reach again.
struct AskAIHeader: View {
  @Environment(MemoraModel.self) private var model
  var onNewChat: () -> Void
  var onHistory: () -> Void
  var onSearch: () -> Void

  var body: some View {
    ZStack {
      HStack {
        Menu {
          Picker("対象", selection: Binding(
            get: { model.aiScope },
            set: { model.changeAIScope($0) }
          )) {
            ForEach(AIChatScope.allCases) { scope in
              Label(scope.title, icon: scope.symbol).tag(scope)
            }
          }
        } label: {
          Image(icon: model.aiScope.symbol)
            .font(.body.weight(.medium))
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .memoraGlass(in: Circle(), interactive: true)
        .accessibilityLabel("対象: \(model.aiScope.title)")

        Spacer()

        HStack(spacing: 0) {
          headerButton("履歴", icon: .clockArrowCirclepath, action: onHistory)
          headerButton("検索", icon: .magnifyingglass, action: onSearch)
          headerButton("新しいチャット", icon: .squareAndPencil, action: onNewChat)
            .disabled(model.aiMessages.isEmpty)
        }
        .padding(.horizontal, 2)
        .memoraGlass(in: Capsule(), interactive: true)
      }
      .padding(.horizontal, 18)
      .frame(maxHeight: .infinity, alignment: .top)

      VStack(spacing: -10) {
        ArtworkIcon(artwork: .askAIHeader, size: 20)
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

  private func headerButton(_ title: String, icon: MemoraIcon, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(icon: icon)
        .font(.body.weight(.medium))
        .frame(width: 40, height: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
  }
}
