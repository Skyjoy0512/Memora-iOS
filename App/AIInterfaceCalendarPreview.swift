import SwiftUI

struct AIInterfaceCalendarPreview: View {
  var events: [AICalendarEventReference]
  var readAt: Date

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      ForEach(events) { event in
        VStack(alignment: .leading, spacing: 4) {
          Label(event.title, icon: .calendar).font(.subheadline.weight(.medium))
          Text(timeText(event)).font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
      }
      Text("取得時点の予定 · \(readAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "ja_JP"))))")
        .font(.caption).foregroundStyle(.secondary)
    }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
  }

  private func timeText(_ event: AICalendarEventReference) -> String {
    let day = event.start.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(Locale(identifier: "ja_JP")))
    if event.isAllDay {
      // EventKit's all-day end is exclusive, including across daylight-saving changes.
      let lastDay = max(event.start, event.end.addingTimeInterval(-1))
      if !Calendar.current.isDate(event.start, inSameDayAs: lastDay) {
        return "\(day)〜\(lastDay.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(Locale(identifier: "ja_JP")))) · 終日"
      }
      return "\(day) · 終日"
    }
    let start = event.start.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "ja_JP")))
    let sameDay = Calendar.current.isDate(event.start, inSameDayAs: event.end)
    let end = event.end.formatted(Date.FormatStyle(date: sameDay ? .omitted : .abbreviated, time: .shortened).locale(Locale(identifier: "ja_JP")))
    return "\(day) · \(start)〜\(end)"
  }
}
