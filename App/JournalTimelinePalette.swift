import SwiftUI
import UIKit

enum JournalTimelinePalette {
  private static var anchors: [(hour: Double, color: UIColor)] {
    [(0, .systemIndigo), (6, .systemOrange), (9, .systemOrange), (12, .systemBlue),
     (18, .systemPurple), (24, .systemIndigo)]
  }

  static func hour(at date: Date, calendar: Calendar = .current) -> Double {
    let components = calendar.dateComponents([.hour, .minute, .second], from: date)
    return Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
      + Double(components.second ?? 0) / 3600
  }

  static func color(at hour: Double, scheme: ColorScheme) -> Color {
    let hour = min(24, max(0, hour))
    let anchors = anchors
    let upperIndex = anchors.firstIndex { $0.hour >= hour } ?? anchors.count - 1
    let lower = anchors[max(0, upperIndex - 1)]
    let upper = anchors[upperIndex]
    let fraction = upper.hour == lower.hour ? 0 : (hour - lower.hour) / (upper.hour - lower.hour)
    let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
    var lowerRed: CGFloat = 0, lowerGreen: CGFloat = 0, lowerBlue: CGFloat = 0, lowerAlpha: CGFloat = 0
    var upperRed: CGFloat = 0, upperGreen: CGFloat = 0, upperBlue: CGFloat = 0, upperAlpha: CGFloat = 0
    lower.color.resolvedColor(with: traits).getRed(&lowerRed, green: &lowerGreen, blue: &lowerBlue, alpha: &lowerAlpha)
    upper.color.resolvedColor(with: traits).getRed(&upperRed, green: &upperGreen, blue: &upperBlue, alpha: &upperAlpha)
    return Color(
      red: Double(lowerRed) + Double(upperRed - lowerRed) * fraction,
      green: Double(lowerGreen) + Double(upperGreen - lowerGreen) * fraction,
      blue: Double(lowerBlue) + Double(upperBlue - lowerBlue) * fraction
    )
  }

  static func gradient(from startHour: Double, to endHour: Double, scheme: ColorScheme) -> Gradient {
    let start = min(24, max(0, startHour))
    let end = min(24, max(start, endHour))
    guard end > start else {
      return Gradient(colors: [color(at: start, scheme: scheme), color(at: start, scheme: scheme)])
    }
    let hours = [start] + anchors.map(\.hour).filter { $0 > start && $0 < end } + [end]
    return Gradient(stops: hours.map { hour in
      Gradient.Stop(color: color(at: hour, scheme: scheme), location: (hour - start) / (end - start))
    })
  }
}
