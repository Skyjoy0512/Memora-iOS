import EventKit
import SwiftUI

/// Which calendars the journal draws from. With none chosen, every calendar is
/// shown, so the common case needs no work.
struct CalendarSelectionView: View {
  @AppStorage("memora.journal.calendarIDs") private var selectedIDsValue = ""
  @State private var calendars: [Row] = []

  private var selectedIDs: [String] {
    selectedIDsValue.isEmpty ? [] : selectedIDsValue.components(separatedBy: "\n")
  }

  private struct Row: Identifiable {
    var id: String
    var title: String
  }

  var body: some View {
    MemoraForm {
      Section {
        if calendars.isEmpty {
          Text("カレンダーが見つかりません。")
            .foregroundStyle(.secondary)
        } else {
          Button {
            selectedIDsValue = ""
          } label: {
            selectionRow("すべてのカレンダー", isSelected: selectedIDs.isEmpty)
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(selectedIDs.isEmpty ? .isSelected : [])

          ForEach(calendars) { calendar in
            let isSelected = selectedIDs.contains(calendar.id)
            Button {
              toggle(calendar.id)
            } label: {
              selectionRow(calendar.title, isSelected: isSelected)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(calendar.title)
            .accessibilityValue(selectedIDs.isEmpty || isSelected ? "表示" : "非表示")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityHint(selectedIDs.isEmpty ? "このカレンダーだけを表示します" : "")
          }
        }
      } footer: {
        Text("個別のカレンダーを選ぶと、表示する予定を絞り込めます。")
      }
    }
    .navigationTitle("表示するカレンダー")
    .navigationBarTitleDisplayMode(.inline)
    .task { await loadCalendars() }
  }

  private func selectionRow(_ title: String, isSelected: Bool) -> some View {
    HStack {
      Text(title).foregroundStyle(.primary)
      Spacer()
      if isSelected {
        Image(icon: .checkmark)
          .foregroundStyle(.primary)
          .accessibilityHidden(true)
      }
    }
    .frame(minHeight: MemoraSpacing.touchTarget)
    .contentShape(Rectangle())
  }

  private func toggle(_ id: String) {
    var ids = selectedIDs
    if let index = ids.firstIndex(of: id) {
      ids.remove(at: index)
    } else {
      ids.append(id)
    }
    selectedIDsValue = ids.joined(separator: "\n")
  }

  private func loadCalendars() async {
    let rows = await Task.detached(priority: .userInitiated) { () -> [Row] in
      EKEventStore().calendars(for: .event).map {
        Row(id: $0.calendarIdentifier, title: $0.title)
      }
    }.value
    calendars = rows
  }
}
