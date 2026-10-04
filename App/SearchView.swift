import SwiftUI

struct SearchView: View {
  @Environment(MemoraModel.self) private var model
  @State private var query = ""
  @State private var isSearchSheetPresented = false
  @State private var isHistoryPresented = false
  @State private var filters = SearchFilters()
  /// Whether the newest message is in view, so scrolling back to read is not
  /// interrupted by a reply arriving.
  @State private var isNearBottom = true
  @State private var hasUnseenAnswer = false
  /// Bumped each time the tab opens, to replay the glow's entrance.
  @State private var glowEntrance = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    @Bindable var model = model

    return NavigationStack {
      // One assistant, one conversation: Memora's mark at the top, the
      // messages below it.
      Group {
        if model.aiMessages.isEmpty {
          chatEmptyState
        } else {
          chatTranscript
        }
      }
      .background {
        AskAIGlow(isThinking: model.isAIChatResponding, isEmpty: model.aiMessages.isEmpty, entrance: glowEntrance)
      }
      .onChange(of: model.selectedTab) { _, tab in
        if tab == .askAI { glowEntrance += 1 }
      }
      .safeAreaInset(edge: .top, spacing: 0) {
        VStack(spacing: 10) {
          assistantHeader
          if model.isRecording {
            ActiveRecordingStrip()
              .padding(.horizontal, 18)
          }
        }
        .padding(.bottom, 8)
        .background {
          // Hides the conversation scrolling under the header, but steps
          // aside while the thinking glow fills the screen.
          LinearGradient(
            colors: [Color(uiColor: .systemBackground), Color(uiColor: .systemBackground).opacity(0)],
            startPoint: .init(x: 0.5, y: 0.75),
            endPoint: .bottom
          )
          .ignoresSafeArea(edges: .top)
          .opacity(model.isAIChatResponding ? 0 : 1)
          .animation(.smooth(duration: 0.9), value: model.isAIChatResponding)
        }
      }
      // Tapping the conversation puts the keyboard away.
      .contentShape(Rectangle())
      .simultaneousGesture(TapGesture().onEnded { dismissKeyboard() })
      .toolbar(.hidden, for: .navigationBar)
      .sheet(isPresented: $isSearchSheetPresented) {
        searchSheet
      }
      .sheet(isPresented: $isHistoryPresented) {
        AIHistoryView(
          entries: model.aiHistory,
          ask: { question in
            isHistoryPresented = false
            Task {
              try? await Task.sleep(for: .milliseconds(250))
              model.sendAIChat(question)
            }
          },
          continueConversation: { entry in
            isHistoryPresented = false
            model.continueAIConversation(from: entry)
          },
          delete: { model.deleteAIHistoryEntry($0) }
        )
      }
    }
  }

  private var chatTranscript: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 14) {
          if let first = model.aiMessages.first {
            Text(first.createdAt.formatted(date: .abbreviated, time: .shortened))
              .font(.caption)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity)
          }
          ForEach(model.aiMessages) { message in
            AIMessageView(message: message, animates: message.id == model.aiMessages.last?.id)
              .id(message.id)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
      }
      .scrollDismissesKeyboard(.interactively)
      .contentMargins(.bottom, model.bottomContentClearance, for: .scrollContent)
      .hideBottomBarOnScroll(RootTab.askAI.rawValue)
      .refreshable { await model.refresh() }
      .onScrollGeometryChange(for: Bool.self) { geometry in
        geometry.contentOffset.y + geometry.containerSize.height
          >= geometry.contentSize.height - 80
      } action: { _, nearBottom in
        isNearBottom = nearBottom
        if nearBottom {
          hasUnseenAnswer = false
        }
      }
      .onChange(of: model.aiMessages.count) { _, _ in
        followLatest(proxy)
      }
      .onChange(of: model.isAIChatResponding) { _, _ in
        followLatest(proxy)
      }
      // An approval card needs to be seen to be answered, so the keyboard
      // steps aside and the card scrolls into view.
      .onChange(of: model.pendingAgentApproval?.id) { _, id in
        guard id != nil else { return }
        dismissKeyboard()
        scrollToLatest(proxy)
      }
      .animation(reduceMotion ? nil : MemoraMotion.control, value: model.pendingAgentApproval?.id)
      .animation(reduceMotion ? nil : MemoraMotion.control, value: model.isAIChatResponding)
      .onAppear {
        scrollToLatest(proxy)
      }
      .overlay(alignment: .bottom) {
        if model.isAIChatResponding {
          // Stopping is offered where the answer is being written.
          Button("停止", icon: .stopFill) {
            model.stopAIChat()
          }
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.primary)
          .padding(.horizontal, 16)
          .padding(.vertical, 9)
          .memoraGlass(in: Capsule(), interactive: true)
          .padding(.bottom, model.bottomContentClearance)
          .transition(.opacity.combined(with: .scale(scale: 0.9)))
          .accessibilityLabel("回答を停止")
        } else if hasUnseenAnswer {
          Button("新しい回答", icon: .arrowDown) {
            hasUnseenAnswer = false
            scrollToLatest(proxy)
          }
          .font(.subheadline.weight(.semibold))
          .padding(.horizontal, 14)
          .padding(.vertical, 9)
          .background(.thinMaterial, in: Capsule())
          .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
          .padding(.bottom, model.bottomContentClearance)
          .accessibilityLabel("新しい回答を表示")
        }
      }
    }
  }

  private func dismissKeyboard() {
    model.composerDismissRequests += 1
  }

  /// Follows the newest message only when the bottom is already in view;
  /// otherwise it offers a button, so reading earlier answers is not yanked away.
  private func followLatest(_ proxy: ScrollViewProxy) {
    guard isNearBottom else {
      hasUnseenAnswer = true
      return
    }
    scrollToLatest(proxy)
  }

  private func scrollToLatest(_ proxy: ScrollViewProxy) {
    guard let last = model.aiMessages.last else { return }
    withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
      proxy.scrollTo(last.id, anchor: .bottom)
    }
  }

  private var chatEmptyState: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        Text(Date.now.formatted(date: .abbreviated, time: .shortened))
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity)
        AskAIGreeting()
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 18)
      .padding(.vertical, 12)
    }
  }

  private var assistantHeader: some View {
    AskAIHeader(
      onNewChat: { model.startNewAIChat() },
      onHistory: { isHistoryPresented = true },
      onSearch: { isSearchSheetPresented = true }
    )
  }

  private var searchSheet: some View {
    NavigationStack {
      Group {
        if query.isEmpty {
          ContentUnavailableView(
            "会話を検索",
            icon: .magnifyingglass,
            description: Text("タイトル、発言、決定、タスクから探せます。")
          )
        } else {
          resultsView
        }
      }
      .navigationTitle("検索")
      .navigationBarTitleDisplayMode(.inline)
      .searchable(text: $query, prompt: "会議、発言、決定、タスク")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("完了", icon: .checkmark) { isSearchSheetPresented = false }
        }
      }
    }
  }

  private var resultsView: some View {
    // Each search walks every record's text, so it runs once per redraw and
    // the list, the animation keys and the empty state share the result.
    let matchingMeetings = model.searchMeetings(matching: query, filters: filters)
    let matchingTasks = model.searchTasks(matching: query, filters: filters)

    return List {
      Section {
        Button {
          isSearchSheetPresented = false
          Task {
            try? await Task.sleep(for: .milliseconds(250))
            model.sendAIChat(query)
          }
        } label: {
          Label("「\(query)」をMemoraに聞く", icon: .sparkles)
            .font(.headline)
            .foregroundStyle(.primary)
            .lineLimit(2)
        }
      }

      if !matchingMeetings.isEmpty {
        Section("会話") {
          ForEach(matchingMeetings) { meeting in
            NavigationLink {
              MeetingDetailView(meetingID: meeting.id)
            } label: {
              MeetingRow(meeting: meeting, showsDisclosure: false)
            }
          }
        }
      }

      if !matchingTasks.isEmpty {
        Section("タスク") {
          ForEach(matchingTasks) { task in
            TaskRow(task: task, showsSource: true)
          }
        }
      }
    }
    .listStyle(.insetGrouped)
    .safeAreaInset(edge: .top, spacing: 0) { filterBar }
    .animation(reduceMotion ? nil : .smooth, value: matchingMeetings.map(\.id))
    .animation(reduceMotion ? nil : .smooth, value: matchingTasks.map(\.id))
    .overlay {
      if matchingMeetings.isEmpty && matchingTasks.isEmpty {
        if filters.isActive {
          ContentUnavailableView {
            Label("条件に合う結果がありません", icon: .line3HorizontalDecreaseCircle)
          } description: {
            Text("絞り込みを変えるか、解除してみてください。")
          } actions: {
            Button("絞り込みを解除") { filters.reset() }
          }
        } else {
          ContentUnavailableView.search(text: query)
        }
      }
    }
  }

  /// Narrows the results by period, person, project and state. Kept above the
  /// results so a filter is never scrolled out of sight while it is applied.
  private var filterBar: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 8) {
        periodMenu
        personMenu
        spaceMenu
        statusMenu
        if filters.isActive {
          Button("解除", icon: .xmarkCircle) {
            filters.reset()
          }
          .font(.subheadline.weight(.medium))
          .padding(.horizontal, 12)
          .padding(.vertical, 7)
          .background(Color.primary.opacity(0.06), in: Capsule())
          .contentShape(Capsule())
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
    }
    .scrollIndicators(.hidden)
    .background(.bar)
  }

  private var periodMenu: some View {
    Menu {
      Picker("期間", selection: $filters.period) {
        ForEach(SearchFilters.Period.allCases) { period in
          Text(period.title).tag(period)
        }
      }
    } label: {
      filterChip(
        title: filters.period == .all ? "期間" : filters.period.title,
        symbol: .calendar,
        isActive: filters.period != .all
      )
    }
    .accessibilityLabel("期間で絞り込む")
  }

  private var personMenu: some View {
    Menu {
      Picker("人", selection: $filters.personID) {
        Text("すべて").tag(UUID?.none)
        ForEach(model.people) { person in
          Text(person.name).tag(UUID?.some(person.id))
        }
      }
    } label: {
      filterChip(
        title: filters.personID.flatMap { model.person(id: $0)?.name } ?? "人",
        symbol: .person,
        isActive: filters.personID != nil
      )
    }
    .accessibilityLabel("人で絞り込む")
  }

  private var spaceMenu: some View {
    Menu {
      Picker("プロジェクト", selection: $filters.spaceID) {
        Text("すべて").tag(UUID?.none)
        ForEach(model.spaces) { space in
          Text(space.name).tag(UUID?.some(space.id))
        }
      }
    } label: {
      filterChip(
        title: filters.spaceID.flatMap { model.space(id: $0)?.name } ?? "プロジェクト",
        symbol: .folder,
        isActive: filters.spaceID != nil
      )
    }
    .accessibilityLabel("プロジェクトで絞り込む")
  }

  private var statusMenu: some View {
    Menu {
      Picker("状態", selection: $filters.status) {
        Text("すべて").tag(SearchFilters.Status?.none)
        ForEach(SearchFilters.Status.allCases) { status in
          Text(status.title).tag(SearchFilters.Status?.some(status))
        }
      }
    } label: {
      filterChip(
        title: filters.status?.title ?? "状態",
        symbol: .checkmarkCircle,
        isActive: filters.status != nil
      )
    }
    .accessibilityLabel("状態で絞り込む")
  }

  private func filterChip(title: String, symbol: MemoraIcon, isActive: Bool) -> some View {
    HStack(spacing: 4) {
      Image(icon: symbol)
      Text(title)
      Image(icon: .chevronDown)
        .font(.caption2.weight(.semibold))
    }
    .font(.subheadline.weight(.medium))
    .foregroundStyle(.primary)
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
    .background(Color.primary.opacity(isActive ? 0.12 : 0.06), in: Capsule())
    .contentShape(Capsule())
  }
}
