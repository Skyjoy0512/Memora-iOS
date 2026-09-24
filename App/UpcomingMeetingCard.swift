import EventKit
import SwiftUI
import UIKit

/// A glance at the next calendar event, with a one-tap record button. In
/// `showsOnlyNextMeeting` mode (used on the Files screen) it draws nothing
/// unless there is a meeting coming up.
struct UpcomingMeetingCard: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.openURL) private var openURL
  @Environment(\.scenePhase) private var scenePhase

  /// When true, the card stays hidden in every state but "a meeting is next".
  var showsOnlyNextMeeting: Bool
  @State private var phase: Phase
  @State private var isStarting = false
  @State private var isLoading = false

  private enum Phase {
    case loading
    case needsAccess
    case denied
    case loaded([UpcomingMeeting])
  }

  init(showsOnlyNextMeeting: Bool = false) {
    self.showsOnlyNextMeeting = showsOnlyNextMeeting
    switch CalendarService.access {
    case .granted: _phase = State(initialValue: .loading)
    case .denied: _phase = State(initialValue: .denied)
    case .unknown: _phase = State(initialValue: .needsAccess)
    }
  }

  var body: some View {
    Group {
      switch phase {
      case .loading:
        collapsed

      case .needsAccess:
        if !showsOnlyNextMeeting {
          promptCard(
            symbol: "calendar.badge.plus",
            title: "カレンダーと接続",
            detail: "次の会議をファイルに表示し、すぐ録音を始められます"
          ) {
            Task { await connect() }
          }
        } else {
          collapsed
        }

      case .denied:
        if !showsOnlyNextMeeting {
          promptCard(
            symbol: "calendar.badge.exclamationmark",
            title: "カレンダーがオフ",
            detail: "設定で許可すると、次の会議からすぐ録音できます"
          ) {
            if let url = URL(string: UIApplication.openSettingsURLString) {
              openURL(url)
            }
          }
        } else {
          collapsed
        }

      case .loaded(let events):
        if let next = events.first {
          nextMeetingCard(next)
        } else if !showsOnlyNextMeeting {
          promptCard(
            symbol: "calendar",
            title: "次の会議はありません",
            detail: "予定が入ると、ここからすぐ録音できます"
          ) {
            Task { await refresh() }
          }
        } else {
          collapsed
        }
      }
    }
    // Reloads whenever the card appears, the app comes back, or the calendar
    // itself changes, so a permission switched on in Settings is picked up too.
    .task { await refresh() }
    .onChange(of: scenePhase) { _, newPhase in
      guard newPhase == .active else { return }
      Task { await refresh() }
    }
    .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
      Task { await refresh() }
    }
  }

  /// Hides the card without leaving an empty row behind.
  private var collapsed: some View {
    Color.clear.frame(height: 0)
  }

  private func nextMeetingCard(_ meeting: UpcomingMeeting) -> some View {
    UpcomingMeetingLiveCard(meeting: meeting, isStarting: isStarting) {
      Task {
        isStarting = true
        await model.startCapture(event: meeting)
        isStarting = false
      }
    }
  }

  private func promptCard(
    symbol: String,
    title: String,
    detail: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: symbol)
          .font(.title3)
          .foregroundStyle(.primary)

        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer(minLength: 8)

        Image(systemName: "chevron.right")
          .font(.caption.bold())
          .foregroundStyle(.tertiary)
      }
      .padding(14)
      .background(
        Color(uiColor: .secondarySystemBackground),
        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
      )
    }
    .buttonStyle(.plain)
  }

  /// Reloads in whatever state the card is in - including "no meetings" and
  /// denied access - so the retry button and a return to the app both work.
  private func refresh() async {
    guard !isLoading else { return }
    isLoading = true
    defer { isLoading = false }

    switch CalendarService.access {
    case .denied:
      phase = .denied
      return
    case .unknown:
      phase = .needsAccess
      return
    case .granted:
      break
    }

    phase = .loaded(await CalendarService.upcoming())
  }

  private func connect() async {
    if await CalendarService.requestAccess() {
      await refresh()
    } else {
      phase = .denied
    }
  }
}
