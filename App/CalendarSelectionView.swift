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
    List {
      Section {
        if calendars.isEmpty {
          Text("カレンダーが見つかりません。")
            .foregroundStyle(.secondary)
        } else {
          ForEach(calendars) { calendar in
            Button {
              toggle(calendar.id)
            } label: {
              HStack {
                Text(calendar.title)
                  .foregroundStyle(.primary)
                Spacer()
                if selectedIDs.contains(calendar.id) {
                  Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
                }
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(calendar.title)
            .accessibilityValue(selectedIDs.contains(calendar.id) ? "表示" : "非表示")
          }
        }
      } footer: {
        Text("選んだカレンダーの予定だけを表示します。未選択ならすべて表示します。")
      }
    }
    .navigationTitle("表示するカレンダー")
    .navigationBarTitleDisplayMode(.inline)
    .task { await loadCalendars() }
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
