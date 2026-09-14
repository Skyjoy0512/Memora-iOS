import SwiftUI

struct FileSidebarView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("ファイル")
          .font(.title.bold())
        Spacer()
        Button("新規作成", systemImage: "plus") {
          model.isFileSidebarPresented = false
          model.isFileCreationPresented = true
        }
        .labelStyle(.iconOnly)
        .font(.title3.weight(.semibold))
        .frame(width: 44, height: 44)
        .memoraGlass(in: Circle(), interactive: true)
      }
      .padding(.horizontal, 20)
      .padding(.top, 62)
      .padding(.bottom, 20)

      VStack(spacing: 6) {
        ForEach(FileSection.allCases) { section in
          Button {
            withAnimation(reduceMotion ? nil : MemoraMotion.screen) {
              model.fileSection = section
              model.libraryPath = []
              model.isFileSidebarPresented = false
            }
          } label: {
            Label(section.title, systemImage: section.symbol)
              .font(.body.weight(model.fileSection == section ? .semibold : .regular))
              .foregroundStyle(.primary)
              .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
              .padding(.horizontal, 14)
              .background {
                if model.fileSection == section {
                  RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                }
              }
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(model.fileSection == section ? .isSelected : [])
        }
      }
      .padding(.horizontal, 14)

      Divider().padding(20)

      Text("選択した種類だけを表示します。ライフログは下の専用タブから確認できます。")
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 24)

      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background(Color(uiColor: .systemBackground))
    .clipShape(.rect(bottomTrailingRadius: 30, topTrailingRadius: 30))
    .shadow(color: .black.opacity(0.12), radius: 24, x: 8)
    .ignoresSafeArea()
    .padding(.trailing, 0)
  }
}
