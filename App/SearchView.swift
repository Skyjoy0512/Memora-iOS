import SwiftUI
import Combine
import UIKit

struct SearchView: View {
  @Environment(MemoraModel.self) private var model
  @State private var query = ""
  @State private var isSearchSheetPresented = false
  @State private var isHistoryPresented = false
  @State private var screenshotShare: AIAnswerShareContent?
  @State private var filters = SearchFilters()
  var isComposing = false
  var onOpenSidebar: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var typeSize

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
      .memoraAppear()
      .background(MemoraPalette.background)
      .safeAreaInset(edge: .top, spacing: 0) {
        VStack(spacing: MemoraSpacing.md) {
          assistantHeader
          if model.isRecording {
            ActiveRecordingStrip()
              .padding(.horizontal, MemoraSpacing.lg)
          }
        }
        .padding(.bottom, MemoraSpacing.sm)
        .background {
          MemoraPalette.background
          .ignoresSafeArea(edges: .top)
          .opacity(model.isAIChatResponding ? 0 : 1)
          .animation(reduceMotion ? nil : .smooth(duration: 0.9), value: model.isAIChatResponding)
        }
      }
      // Tapping the conversation puts the keyboard away.
      .contentShape(Rectangle())
      .simultaneousGesture(TapGesture().onEnded { dismissKeyboard() })
      .toolbar(.hidden, for: .navigationBar)
      .onChange(of: model.sidebarSearchRequest) { _, request in
        guard request != nil, model.selectedTab == .askAI, !model.isToolsPresented else { return }
        isSearchSheetPresented = true
      }
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
      // iOS tells the app after a screenshot is taken; the answer on screen
      // can then be offered as a card instead of the raw capture.
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
        presentScreenshotShare()
      }
      .sheet(item: $screenshotShare) { content in
        AIAnswerShareSheet(content: content)
      }
    }
  }

  private func presentScreenshotShare() {
    guard model.selectedTab == .askAI,
          !model.isToolsPresented,
          !isSearchSheetPresented,
          !isHistoryPresented,
          screenshotShare == nil,
          let answer = model.aiMessages.last(where: {
            $0.role == .assistant && !$0.isThinking && !$0.text.isEmpty
          })
    else { return }
    screenshotShare = model.answerShareContent(for: answer)
  }

  private var chatTranscript: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: MemoraSpacing.section) {
          if let first = model.aiMessages.first {
            Text(first.createdAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "ja_JP"))))
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
      // The pull that starts a new chat needs the rubber band even when the
      // conversation is shorter than the screen.
      .scrollBounceBehavior(.always)
      .modifier(ConversationScrollFollowing(proxy: proxy, latestMessageID: model.aiMessages.last?.id,
        isBusy: model.isAIChatResponding, bottomInset: model.bottomContentClearance))
      .modifier(ConversationPullToNewChat {
        model.startNewAIChat()
      })
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
    AgentPromptSuggestionsView(isComposing: isComposing)
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
      VStack(spacing: 0) {
        if CollectionSearch.hasQuery(query) { filterBar }
        resultsView
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
    let hasQuery = CollectionSearch.hasQuery(query)
    let matchingMeetings = hasQuery ? model.searchMeetings(matching: query, filters: filters) : []
    let matchingTasks = hasQuery ? model.searchTasks(matching: query, filters: filters) : []

    return List {
      if !hasQuery {
        Section {
          CollectionSearchState(title: "会話を検索",
            message: "タイトル、発言、決定、タスクから探せます。", isEmbedded: true)
        }
        .listRowSeparator(.hidden)
      } else {
        Section {
          Button {
            let question = query.trimmingCharacters(in: .whitespacesAndNewlines)
            isSearchSheetPresented = false
            Task {
              try? await Task.sleep(for: .milliseconds(250))
              model.sendAIChat(question)
            }
          } label: {
            Label("検索語をMemoraに聞く", icon: .sparkles)
              .font(.headline)
              .foregroundStyle(.primary)
              .frame(maxWidth: .infinity, minHeight: MemoraSpacing.touchTarget, alignment: .leading)
              .contentShape(Rectangle())
          }
          .accessibilityHint("入力した検索語を質問として送信します")
        }

        if matchingMeetings.isEmpty && matchingTasks.isEmpty {
          Section {
            if filters.isActive {
              CollectionSearchState(title: "条件に合う結果がありません",
                message: "絞り込みを解除するか、別の語句を入力してください。",
                clear: { filters.reset() }, clearTitle: "絞り込みを解除", isEmbedded: true)
            } else {
              CollectionSearchState(title: "見つかりませんでした",
                message: "別の語句を入力してください。", isEmbedded: true)
            }
          }
          .listRowSeparator(.hidden)
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
    }
    .memoraPlainList()
  }

  /// Narrows the results by period, person, project and state. Kept above the
  /// results so a filter is never scrolled out of sight while it is applied.
  private var filterBar: some View {
    Group {
      if typeSize.isAccessibilitySize {
        Menu {
          periodMenu
          personMenu
          spaceMenu
          statusMenu
          if filters.isActive { Button("絞り込みを解除") { filters.reset() } }
        } label: {
          filterChip(title: filters.isActive ? "絞り込み中" : "絞り込み",
            symbol: .line3HorizontalDecrease, isActive: filters.isActive)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, MemoraSpacing.lg)
      } else {
        ScrollView(.horizontal) {
          HStack(spacing: MemoraSpacing.sm) {
            periodMenu
            personMenu
            spaceMenu
            statusMenu
            if filters.isActive {
              Button { filters.reset() } label: {
                filterChip(title: "解除", symbol: .xmarkCircle, isActive: false, showsMenuIndicator: false)
              }
              .accessibilityLabel("絞り込みを解除")
            }
          }
          .padding(.horizontal, MemoraSpacing.lg)
        }
        .scrollIndicators(.hidden)
      }
    }
    .padding(.vertical, MemoraSpacing.sm)
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
    .accessibilityValue(filters.period.title)
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
    .accessibilityValue(filters.personID.flatMap { model.person(id: $0)?.name } ?? "すべて")
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
    .accessibilityValue(filters.spaceID.flatMap { model.space(id: $0)?.name } ?? "すべて")
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
    .accessibilityValue(filters.status?.title ?? "すべて")
  }

  private func filterChip(title: String, symbol: MemoraIcon, isActive: Bool, showsMenuIndicator: Bool = true) -> some View {
    HStack(spacing: MemoraSpacing.xs) {
      Image(icon: symbol, size: 11)
      Text(title)
      if showsMenuIndicator { Image(icon: .chevronDown, size: 11) }
    }
    .font(.subheadline.weight(.medium))
    .foregroundStyle(.primary)
    .padding(.horizontal, MemoraSpacing.md)
    .padding(.vertical, MemoraSpacing.sm)
    .frame(minHeight: MemoraSpacing.touchTarget)
    .background(Color.primary.opacity(isActive ? 0.12 : 0.06), in: Capsule())
    .contentShape(Capsule())
  }
}
