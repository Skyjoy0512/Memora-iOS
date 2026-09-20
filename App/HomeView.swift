import SwiftUI

/// The landing screen. It answers "what happened today" first, then lets the
/// day unroll as a timeline of everything Memora captured.
struct HomeView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var query = ""
  @State private var isCreationPresented = false
  @State private var selectedPersonID: UUID?
  @State private var isManagingPeople = false
  /// The day the Journal is showing.
  @State private var selectedDate = Calendar.current.startOfDay(for: .now)
  /// The day "today" meant when the screen was last seen, so a journal left
  /// open past midnight follows the new day.
  @State private var todayAnchor = Calendar.current.startOfDay(for: .now)
  var onOpenSidebar: () -> Void

  var body: some View {
    @Bindable var model = model
    let entries = matchingEntries

    NavigationStack(path: $model.homePath) {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 18) {
          PeopleStrip(
            people: model.people,
            selectedID: selectedPersonID,
            onSelect: { selectedPersonID = $0 },
            onManage: { isManagingPeople = true }
          )

          if query.isEmpty {
            JournalCalendar(selectedDate: $selectedDate, markedDays: markedDays)
          }

          if query.isEmpty, selectedPerson == nil {
            UpcomingMeetingCard()
          }

          if let person = selectedPerson {
            filterHeader(person)
          }

          if entries.isEmpty {
            VStack(spacing: 16) {
              Image(systemName: "waveform.path.ecg")
                .font(.title2)
                .foregroundStyle(.secondary)

              VStack(spacing: 6) {
                Text(selectedPerson == nil ? "まだライフログがありません" : "この人の記録はありません")
                  .font(.headline)

                Text(emptyDescription)
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
                  .multilineTextAlignment(.center)
              }

              if query.isEmpty {
                Button("記録を追加") {
                  isCreationPresented = true
                }
                .font(.headline)
                .foregroundStyle(Color(uiColor: .systemBackground))
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color(uiColor: .label), in: Capsule())
                .contentShape(Capsule())
                .buttonStyle(.plain)
              }
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .memoraCard()
          } else {
            if !query.isEmpty {
              Text("検索結果")
                .font(.title2.bold())
                .memoraTextReveal()
            }

            ForEach(dayGroups(of: entries)) { group in
              VStack(alignment: .leading, spacing: 10) {
                Text(dayLabel(for: group.day))
                  .font(.title2.bold())
                  .memoraTextReveal()

                LazyVStack(spacing: 0) {
                  ForEach(group.entries) { entry in
                    if let meetingID = entry.meetingID {
                      NavigationLink(value: LibraryRoute.meeting(meetingID)) {
                        LifeLogRow(entry: entry)
                      }
                      .buttonStyle(.plain)
                    } else {
                      LifeLogRow(entry: entry)
                    }
                  }
                }
              }
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.bottom, 32)
      }
      .hideBottomBarOnScroll()
      .background(Color(uiColor: .systemBackground))
      .navigationTitle("ジャーナル")
      .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "記録を検索")
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("メニュー", systemImage: "line.3.horizontal") {
            onOpenSidebar()
          }
          .labelStyle(.iconOnly)
        }

        ToolbarItem(placement: .topBarLeading) {
          sourceStatusButton
        }

        ToolbarItem(placement: .topBarTrailing) {
          Button("記録を追加", systemImage: "plus") {
            isCreationPresented = true
          }
          .labelStyle(.iconOnly)
        }

        ToolbarItem(placement: .topBarTrailing) {
          Button("設定", systemImage: "gearshape") {
            model.isSettingsPresented = true
          }
          .labelStyle(.iconOnly)
        }
      }
      .sheet(isPresented: $isCreationPresented) {
        LifeLogCreationSheet()
      }
      .sheet(isPresented: $isManagingPeople) {
        PeopleManagerSheet()
      }
      .onChange(of: model.people.map(\.id)) { _, ids in
        if let id = selectedPersonID, !ids.contains(id) {
          selectedPersonID = nil
        }
      }
      .onChange(of: scenePhase) { _, phase in
        guard phase == .active else { return }
        refreshTodayIfNeeded()
      }
      .navigationDestination(for: LibraryRoute.self) { route in
        switch route {
        case .meeting(let id): MeetingDetailView(meetingID: id)
        case .transcript(let id): TranscriptView(meetingID: id)
        case .space(let id): SpaceDetailView(spaceID: id)
        case .allMeetings: AllMeetingsView()
        case .settings: SettingsView()
        case .stateGallery: StateGalleryView()
        }
      }
    }
  }

  /// The lifelog connection lives beside the menu so the journal itself keeps
  /// the full screen.
  private var sourceStatusButton: some View {
    Button {
      model.isSettingsPresented = true
    } label: {
      Label("Omi", systemImage: isOmiConnected ? "dot.radiowaves.left.and.right" : "link")
        .font(.subheadline.weight(.medium))
        .foregroundStyle(isOmiConnected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
    }
    .accessibilityLabel(isOmiConnected ? "Omi 接続中" : "ライフログの接続先")
    .accessibilityHint("レコーダー設定を開きます")
  }

  /// Days that hold at least one record, for the calendar's dot.
  private var markedDays: Set<Date> {
    Set(model.lifeLogEntries.map { Calendar.current.startOfDay(for: $0.createdAt) })
  }

  /// A journal left open past midnight should move to the new day, unless the
  /// person had picked another day themselves.
  private func refreshTodayIfNeeded() {
    let today = Calendar.current.startOfDay(for: .now)
    guard today != todayAnchor else { return }
    if selectedDate == todayAnchor {
      selectedDate = today
    }
    todayAnchor = today
  }

  private var isOmiConnected: Bool {
    if case .connected = model.omiPairingManager.state { return true }
    return false
  }

  private var matchingEntries: [LifeLogEntry] {
    let sorted = model.newestLifeLogEntries

    let scoped: [LifeLogEntry]
    if let personID = selectedPerson?.id {
      let meetingIDs = Set(model.meetings(withPerson: personID).map(\.id))
      scoped = sorted.filter { entry in
        guard let meetingID = entry.meetingID else { return false }
        return meetingIDs.contains(meetingID)
      }
    } else {
      scoped = sorted
    }

    if !query.isEmpty {
      return scoped.filter {
        $0.title.localizedCaseInsensitiveContains(query)
          || $0.summary.localizedCaseInsensitiveContains(query)
          || $0.source.label.localizedCaseInsensitiveContains(query)
      }
    }

    // The journal shows the day picked in the calendar.
    return scoped.filter { Calendar.current.isDate($0.createdAt, inSameDayAs: selectedDate) }
  }

  private var selectedPerson: Person? {
    selectedPersonID.flatMap { model.person(id: $0) }
  }

  private var emptyDescription: String {
    if !query.isEmpty {
      return "「\(query)」に一致する記録はありません。"
    }
    if let person = selectedPerson {
      return "\(person.name)さんにひもづいた記録はまだありません。会議の詳細から参加者に追加できます。"
    }
    return "録音やOmiから届いた記録、手で足したメモが時間順に並びます。"
  }

  private func filterHeader(_ person: Person) -> some View {
    HStack(spacing: 10) {
      PersonAvatar(name: person.name, size: 30, photoData: person.photoData)

      Text("\(person.name)の記録")
        .font(.title3.bold())

      Spacer()

      Button("解除") {
        withAnimation(reduceMotion ? nil : MemoraMotion.screen) {
          selectedPersonID = nil
        }
      }
      .font(.subheadline)
    }
  }

  private func dayGroups(of entries: [LifeLogEntry]) -> [LifeLogDayGroup] {
    let grouped = Dictionary(grouping: entries) {
      Calendar.current.startOfDay(for: $0.createdAt)
    }
    return grouped
      .map { LifeLogDayGroup(day: $0.key, entries: $0.value.sorted { $0.createdAt > $1.createdAt }) }
      .sorted { $0.day > $1.day }
  }

  private func dayLabel(for day: Date) -> String {
    if Calendar.current.isDateInToday(day) { return "今日" }
    if Calendar.current.isDateInYesterday(day) { return "昨日" }
    return day.formatted(date: .abbreviated, time: .omitted)
  }
}

private struct LifeLogDayGroup: Identifiable {
  var day: Date
  var entries: [LifeLogEntry]
  var id: Date { day }
}
