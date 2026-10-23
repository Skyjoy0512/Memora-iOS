import SwiftUI

struct SearchView: View {
  @Environment(MemoraModel.self) private var model
  @State private var query = ""
  @State private var isSearchSheetPresented = false
  @State private var isHistoryPresented = false
  @State private var filters = SearchFilters()
  var onOpenSidebar: () -> Void
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
        AskAIGlow(isThinking: model.isAIChatResponding, isEmpty: false, entrance: 0, permitsIdleGlow: false)
      }
      .background(MemoraPalette.background)
      .safeAreaInset(edge: .top, spacing: 0) {
        VStack(spacing: 10) {
          assistantHeader
          if model.isRecording {
            ActiveRecordingStrip()
              .padding(.horizontal, MemoraSpacing.lg)
          }
        }
        .padding(.bottom, MemoraSpacing.sm)
        .background {
          // Hides the conversation scrolling under the header, but steps
          // aside while the thinking glow fills the screen.
          MemoraPalette.background
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
        LazyVStack(alignment: .leading, spacing: MemoraSpacing.section) {
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
          Color.clear.frame(height: 1).id(ConversationScrollFollowing.bottomID)
        }
        .frame(maxWidth: MemoraSpacing.readingWidth, alignment: .leading)
        .padding(.horizontal, MemoraSpacing.screen)
        .padding(.vertical, MemoraSpacing.xxl)
        .frame(maxWidth: .infinity)
      }
      .scrollDismissesKeyboard(.interactively)
      .contentMargins(.bottom, model.bottomContentClearance, for: .scrollContent)
      .refreshable { await model.refresh() }
      .modifier(ConversationScrollFollowing(proxy: proxy, latestMessageID: model.aiMessages.last?.id,
        isBusy: model.isAIChatResponding, bottomInset: model.bottomContentClearance))
      // An approval card needs to be seen to be answered, so the keyboard
      // steps aside and the card scrolls into view.
      .onChange(of: model.pendingAgentApproval?.id) { _, id in
        guard id != nil else { return }
        dismissKeyboard()
        scrollToLatest(proxy)
      }
    }
  }

  private func dismissKeyboard() {
    model.composerDismissRequests += 1
  }

  private func scrollToLatest(_ proxy: ScrollViewProxy) {
    withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
      proxy.scrollTo(ConversationScrollFollowing.bottomID, anchor: .bottom)
    }
  }

  private var chatEmptyState: some View {
    AgentPromptSuggestionsView()
  }

  private var assistantHeader: some View {
    AskAIHeader(
      onOpenSidebar: onOpenSidebar,
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
    .memoraPlainList()
    .safeAreaInset(edge: .top, spacing: 0) { filterBar }
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
          .padding(.horizontal, MemoraSpacing.md)
          .padding(.vertical, 7)
          .background(Color.primary.opacity(0.06), in: Capsule())
          .contentShape(Capsule())
        }
      }
      .padding(.horizontal, MemoraSpacing.lg)
      .padding(.vertical, MemoraSpacing.sm)
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
      Image(icon: symbol, size: 11)
      Text(title)
      Image(icon: .chevronDown, size: 11)
        .font(.caption2.weight(.semibold))
    }
    .font(.subheadline.weight(.medium))
    .foregroundStyle(.primary)
    .padding(.horizontal, MemoraSpacing.md)
    .padding(.vertical, 7)
    .background(Color.primary.opacity(isActive ? 0.12 : 0.06), in: Capsule())
    .contentShape(Capsule())
  }
}
