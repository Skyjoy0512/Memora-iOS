import SwiftUI
import UIKit

/// The Journal's week strip: a horizontally scrolling row of days. Picking a
/// day filters the records below it, and a day that holds a record carries a
/// dot.
struct JournalCalendar: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Binding var selectedDate: Date
  /// Start-of-day dates that have at least one record.
  var markedDays: Set<Date>
  /// Ties the day capsules together so the selection morphs between days.
  @Namespace private var glassNamespace

  private let calendar = Calendar.current
  /// The days the strip can scroll through, anchored on today so the set keeps
  /// its identity while the selection changes.
  private let stripDays: [Date]

  private static let cellWidth: CGFloat = 52
  private static let cellHeight: CGFloat = 80
  private static let cellSpacing: CGFloat = 2
  private static let verticalPadding: CGFloat = 12

  init(selectedDate: Binding<Date>, markedDays: Set<Date>) {
    _selectedDate = selectedDate
    self.markedDays = markedDays
    stripDays = Self.makeStripDays()
  }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView(.horizontal) {
        // The container lets the selected day's capsule grow under the finger
        // and morph into the next day's as the selection moves. The system
        // draws the press, so the day's text stays centred — scaling the cell
        // ourselves pulled the text off centre because the container renders
        // the glass separately from the scaled content.
        MemoraGlassContainer(spacing: 4) {
          LazyHStack(spacing: Self.cellSpacing) {
            ForEach(stripDays, id: \.self) { day in
              dayCell(day).id(day)
            }
          }
          .scrollTargetLayout()
          .padding(.vertical, Self.verticalPadding)
        }
      }
      .scrollTargetBehavior(.viewAligned)
      .scrollIndicators(.hidden)
      .onAppear {
        // The scroll targets need a pass of layout before they exist.
        DispatchQueue.main.async { scroll(proxy, to: selectedDate, animated: false) }
      }
      .onChange(of: selectedDate) { _, day in
        scroll(proxy, to: day, animated: true)
      }
    }
    .frame(height: Self.cellHeight + Self.verticalPadding * 2)
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

  private func dayCell(_ day: Date) -> some View {
    let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
    let isToday = calendar.isDateInToday(day)
    let isMarked = markedDays.contains(calendar.startOfDay(for: day))
    let weekdayStyle: AnyShapeStyle = isSelected ? AnyShapeStyle(MemoraPalette.textPrimary) : AnyShapeStyle(.secondary)
    let dayStyle: AnyShapeStyle = isSelected
      ? AnyShapeStyle(MemoraPalette.textPrimary)
      : (isToday ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))

    return Button {
      if !isSelected { InteractionFeedback.shared.send(.selection) }
      withAnimation(reduceMotion ? nil : MemoraMotion.control) {
        selectedDate = calendar.startOfDay(for: day)
      }
    } label: {
      VStack(spacing: 6) {
        Text(weekdaySymbol(for: day))
          .font(.subheadline)
          .foregroundStyle(weekdayStyle)

        Text(day.formatted(.dateTime.day()))
          .font(.title2.weight(isSelected ? .semibold : .regular))
          .foregroundStyle(dayStyle)
      }
      .frame(width: Self.cellWidth, height: Self.cellHeight)
      // The record dot is an overlay so it never shifts the day off the
      // capsule's centre.
      .overlay(alignment: .bottom) {
        Circle()
          .fill(isMarked ? weekdayStyle : AnyShapeStyle(.clear))
          .frame(width: 4, height: 4)
          .padding(.bottom, 8)
      }
      .modifier(
        DaySelectionGlass(isSelected: isSelected, day: day, namespace: glassNamespace)
      )
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

  /// The weekday name shown above a day, in the calendar's own symbols.
  private func weekdaySymbol(for day: Date) -> String {
    let symbols = calendar.shortWeekdaySymbols
    let index = calendar.component(.weekday, from: day) - 1
    return symbols[(index % symbols.count + symbols.count) % symbols.count]
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

/// Gives the selected day an interactive Liquid Glass capsule. Each day carries
/// its own identifier so the capsule morphs into the next day's as the
/// selection moves, and the system draws the press reaction.
private struct DaySelectionGlass: ViewModifier {
  var isSelected: Bool
  var day: Date
  var namespace: Namespace.ID

  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      if isSelected {
        content
          .glassEffect(.regular.interactive(), in: Capsule())
          .glassEffectID(day, in: namespace)
          .glassEffectTransition(.matchedGeometry)
      } else {
        content
      }
    } else {
      content.background {
        if isSelected { Capsule().fill(Color(uiColor: .tertiarySystemFill)) }
      }
    }
  }
}
