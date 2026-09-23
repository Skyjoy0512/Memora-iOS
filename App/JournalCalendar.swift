import SwiftUI
import UIKit

/// The Journal's calendar: a horizontally scrolling day strip that opens into a
/// month grid. Picking a day filters the records below it, and days that hold a
/// record carry a dot.
struct JournalCalendar: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Binding var selectedDate: Date
  /// Start-of-day dates that have at least one record.
  var markedDays: Set<Date>
  @State private var isExpanded = false
  @State private var visibleMonth: Date

  private let calendar = Calendar.current
  /// The days the strip can scroll through, anchored on today so the set keeps
  /// its identity while the selection changes.
  private let stripDays: [Date]

  init(selectedDate: Binding<Date>, markedDays: Set<Date>) {
    _selectedDate = selectedDate
    self.markedDays = markedDays
    _visibleMonth = State(initialValue: selectedDate.wrappedValue)
    stripDays = Self.makeStripDays()
  }

  var body: some View {
    VStack(spacing: 14) {
      header

      if isExpanded {
        weekdayHeader

        LazyVGrid(columns: columns, spacing: 8) {
          ForEach(Array(gridDays.enumerated()), id: \.offset) { _, day in
            if let day {
              dayCell(day)
            } else {
              Color.clear.frame(height: 46)
            }
          }
        }
      } else {
        dayStrip
      }
    }
    .padding(16)
    .background(
      Color(uiColor: .secondarySystemBackground),
      in: RoundedRectangle(cornerRadius: 22, style: .continuous)
    )
    .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    // A sideways flick moves a month when the grid is open. The day strip has
    // its own scroll view, so the gesture stays out of its way.
    .simultaneousGesture(
      DragGesture(minimumDistance: 24).onEnded { value in
        guard isExpanded else { return }
        guard abs(value.translation.width) > abs(value.translation.height) else { return }
        if value.translation.width < -44 {
          shiftMonth(1)
        } else if value.translation.width > 44 {
          shiftMonth(-1)
        }
      }
    )
    .animation(reduceMotion ? nil : MemoraMotion.control, value: isExpanded)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: visibleMonth)
  }

  /// The scrolling strip of days, with the selected day held near the middle.
  private var dayStrip: some View {
    ScrollViewReader { proxy in
      ScrollView(.horizontal) {
        LazyHStack(spacing: 4) {
          ForEach(stripDays, id: \.self) { day in
            stripCell(day).id(day)
          }
        }
        .scrollTargetLayout()
        .padding(.horizontal, 4)
      }
      .scrollTargetBehavior(.viewAligned)
      .scrollIndicators(.hidden)
      .frame(height: 112)
      .onAppear {
        // The scroll targets need a pass of layout before they exist.
        DispatchQueue.main.async { scroll(proxy, to: selectedDate, animated: false) }
      }
      .onChange(of: selectedDate) { _, day in
        scroll(proxy, to: day, animated: true)
      }
    }
  }

  private func scroll(_ proxy: ScrollViewProxy, to day: Date, animated: Bool) {
    let target = calendar.startOfDay(for: day)
    guard stripDays.contains(target) else { return }
    if animated, !reduceMotion {
      withAnimation(MemoraMotion.control) { proxy.scrollTo(target, anchor: .center) }
    } else {
      proxy.scrollTo(target, anchor: .center)
    }
  }

  private func stripCell(_ day: Date) -> some View {
    let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
    let isToday = calendar.isDateInToday(day)
    let isMarked = markedDays.contains(calendar.startOfDay(for: day))
    let weekdayStyle: AnyShapeStyle = isSelected ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary)
    let dayStyle: AnyShapeStyle = isSelected
      ? AnyShapeStyle(Color.red)
      : (isToday ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))

    return Button {
      withAnimation(reduceMotion ? nil : MemoraMotion.control) {
        selectedDate = calendar.startOfDay(for: day)
        visibleMonth = day
      }
    } label: {
      VStack(spacing: 6) {
        Text(weekdaySymbol(for: day))
          .font(.subheadline)
          .foregroundStyle(weekdayStyle)

        Text(day.formatted(.dateTime.day()))
          .font(.title2.weight(isSelected ? .semibold : .regular))
          .foregroundStyle(dayStyle)

        Circle()
          .fill(isMarked ? weekdayStyle : AnyShapeStyle(.clear))
          .frame(width: 4, height: 4)
      }
      .frame(width: 60, height: 104)
      .background {
        if isSelected {
          Capsule()
            .fill(Color(uiColor: .systemBackground))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.06), radius: 5, y: 2)
        }
      }
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(accessibilityLabel(for: day, isMarked: isMarked))
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  /// Returns the calendar to today from wherever it was left.
  private func goToToday() {
    let today = calendar.startOfDay(for: .now)
    selectedDate = today
    visibleMonth = today
  }

  /// Moves to the next or previous week, or month when expanded.
  private func shift(_ delta: Int) {
    if isExpanded {
      shiftMonth(delta)
      return
    }

    guard let next = calendar.date(byAdding: .weekOfYear, value: delta, to: selectedDate) else { return }
    selectedDate = calendar.startOfDay(for: next)
    visibleMonth = next
  }

  private var previousLabel: String {
    isExpanded ? "前の月" : "前の週"
  }

  private var nextLabel: String {
    isExpanded ? "次の月" : "次の週"
  }

  private var header: some View {
    HStack(spacing: 10) {
      Text(monthTitle)
        .font(.headline)

      Spacer()

      if !calendar.isDateInToday(selectedDate) {
        Button("今日") {
          goToToday()
        }
        .font(.subheadline.weight(.semibold))
      }

      Button(previousLabel, systemImage: "chevron.left") {
        shift(-1)
      }
      .labelStyle(.iconOnly)
      .accessibilityLabel(previousLabel)

      Button(nextLabel, systemImage: "chevron.right") {
        shift(1)
      }
      .labelStyle(.iconOnly)
      .accessibilityLabel(nextLabel)

      Button(
        isExpanded ? "週に戻す" : "月を表示",
        systemImage: isExpanded ? "chevron.up" : "chevron.down"
      ) {
        withAnimation(reduceMotion ? nil : MemoraMotion.control) {
          isExpanded.toggle()
        }
      }
      .labelStyle(.iconOnly)
      .font(.subheadline.weight(.semibold))
    }
  }

  private var weekdayHeader: some View {
    LazyVGrid(columns: columns, spacing: 8) {
      ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
        Text(symbol)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity)
      }
    }
  }

  private func dayCell(_ day: Date) -> some View {
    let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
    let isToday = calendar.isDateInToday(day)
    let isMarked = markedDays.contains(calendar.startOfDay(for: day))

    return Button {
      selectedDate = calendar.startOfDay(for: day)
      visibleMonth = day
    } label: {
      VStack(spacing: 4) {
        Text(day.formatted(.dateTime.day()))
          .font(.subheadline.weight(isSelected ? .semibold : .regular))
          .foregroundStyle(isSelected ? AnyShapeStyle(Color(uiColor: .systemBackground)) : AnyShapeStyle(.primary))
          .frame(width: 30, height: 30)
          .background {
            if isSelected {
              Circle().fill(.primary)
            } else if isToday {
              Circle().strokeBorder(Color.primary.opacity(0.35), lineWidth: 1)
            }
          }

        Circle()
          .fill(isMarked ? AnyShapeStyle(.secondary) : AnyShapeStyle(.clear))
          .frame(width: 4, height: 4)
      }
      .frame(maxWidth: .infinity, minHeight: 46)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(accessibilityLabel(for: day, isMarked: isMarked))
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  /// Reads the date and whether that day holds a record, which the dot shows
  /// only visually.
  private func accessibilityLabel(for day: Date, isMarked: Bool) -> String {
    let date = day.formatted(date: .long, time: .omitted)
    return isMarked ? "\(date)、記録あり" : "\(date)、記録なし"
  }

  private var columns: [GridItem] {
    Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
  }

  private var monthTitle: String {
    (isExpanded ? visibleMonth : selectedDate).formatted(.dateTime.year().month())
  }

  private var weekdaySymbols: [String] {
    let symbols = calendar.veryShortWeekdaySymbols
    let shift = max(0, calendar.firstWeekday - 1) % max(1, symbols.count)
    return Array(symbols[shift...] + symbols[..<shift])
  }

  /// The weekday name shown above a strip day, in the calendar's own symbols.
  private func weekdaySymbol(for day: Date) -> String {
    let symbols = calendar.shortWeekdaySymbols
    let index = calendar.component(.weekday, from: day) - 1
    return symbols[(index % symbols.count + symbols.count) % symbols.count]
  }

  /// The days to draw in the month grid, padded so the 1st lands under its
  /// weekday.
  private var gridDays: [Date?] {
    guard let interval = calendar.dateInterval(of: .month, for: visibleMonth) else {
      return []
    }

    var days: [Date?] = []

    let firstWeekday = calendar.component(.weekday, from: interval.start)
    let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
    days.append(contentsOf: Array(repeating: nil, count: leading))

    var day = calendar.startOfDay(for: interval.start)
    while day < interval.end {
      days.append(day)
      guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
      day = next
    }

    return days
  }

  private func shiftMonth(_ delta: Int) {
    guard let next = calendar.date(byAdding: .month, value: delta, to: visibleMonth) else { return }
    visibleMonth = next
  }

  /// Roughly two years of days, centred on today, so the strip can be flicked
  /// far in either direction.
  private static func makeStripDays() -> [Date] {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: .now)
    guard let start = calendar.date(byAdding: .day, value: -400, to: today),
          let end = calendar.date(byAdding: .day, value: 400, to: today) else {
      return [today]
    }

    var days: [Date] = []
    var day = start
    while day <= end {
      days.append(day)
      guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
      day = next
    }
    return days
  }
}
