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
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    @Bindable var model = model

    return NavigationStack {
      VStack(spacing: 0) {
        if model.isRecording {
          ActiveRecordingStrip()
            .padding(.horizontal, 18)
            .padding(.bottom, 10)
        }

        Group {
          if model.aiMessages.isEmpty {
            chatEmptyState
          } else {
            chatTranscript
          }
        }
      }
      // Tapping the conversation puts the keyboard away.
      .contentShape(Rectangle())
      .simultaneousGesture(TapGesture().onEnded { dismissKeyboard() })
      .navigationTitle("Ask AI")
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Menu {
            Picker("対象", selection: Binding(
              get: { model.aiScope },
              set: { model.changeAIScope($0) }
            )) {
              ForEach(AIChatScope.allCases) { scope in
                Label(scope.title, systemImage: scope.symbol).tag(scope)
              }
            }
          } label: {
            HStack(spacing: 4) {
              Image(systemName: model.aiScope.symbol)
              Text(model.aiScope.title)
              Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
            }
            .font(.subheadline.weight(.medium))
          }
          .accessibilityLabel("対象: \(model.aiScope.title)")
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
          Button("検索", systemImage: "magnifyingglass") {
            isSearchSheetPresented = true
          }
          .labelStyle(.iconOnly)

          Button("履歴", systemImage: "clock.arrow.circlepath") {
            isHistoryPresented = true
          }
          .labelStyle(.iconOnly)

          Button("新しいチャット", systemImage: "square.and.pencil") {
            model.startNewAIChat()
          }
          .labelStyle(.iconOnly)
          .disabled(model.aiMessages.isEmpty)
        }
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
          delete: { model.deleteAIHistoryEntry($0) }
        )
      }
    }
  }

  private var chatTranscript: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 22) {
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
      .onAppear {
        scrollToLatest(proxy)
      }
      .overlay(alignment: .bottom) {
        if hasUnseenAnswer {
          Button("新しい回答", systemImage: "arrow.down") {
            hasUnseenAnswer = false
            scrollToLatest(proxy)
          }
          .font(.subheadline.weight(.semibold))
          .padding(.horizontal, 14)
          .padding(.vertical, 9)
          .background(.thinMaterial, in: Capsule())
          .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
          .padding(.bottom, 12)
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
      VStack(alignment: .leading, spacing: 26) {
        Spacer(minLength: 48)

        VStack(alignment: .leading, spacing: 8) {
          Text("何を知りたいですか？")
            .font(.largeTitle.bold())
            .memoraTextReveal()
          Text("会議をまたいで、意味から答えを探します。")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .memoraTextReveal(delay: 0.08)
        }

        VStack(spacing: 4) {
          ForEach(Self.suggestions, id: \.title) { suggestion in
            Button {
              model.sendAIChat(suggestion.title)
            } label: {
              HStack(spacing: 14) {
                Image(systemName: suggestion.symbol)
                  .font(.body.weight(.medium))
                  .foregroundStyle(.primary)
                  .frame(width: 34, height: 34)
                  .background(
                    Color.primary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                  )

                Text(suggestion.title)
                  .font(.body)
                  .foregroundStyle(.primary)
                  .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
              }
              .padding(.vertical, 8)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        }

        Spacer(minLength: 48)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 18)
    }
  }

  private var searchSheet: some View {
    NavigationStack {
      Group {
        if query.isEmpty {
          ContentUnavailableView(
            "会話を検索",
            systemImage: "magnifyingglass",
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
          Button("完了") { isSearchSheetPresented = false }
        }
      }
    }
  }

  private var resultsView: some View {
    List {
      Section {
        Button {
          isSearchSheetPresented = false
          Task {
            try? await Task.sleep(for: .milliseconds(250))
            model.sendAIChat(query)
          }
        } label: {
          Label("「\(query)」をMemoraに聞く", systemImage: "sparkles")
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
            Label("条件に合う結果がありません", systemImage: "line.3.horizontal.decrease.circle")
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

  private var matchingMeetings: [Meeting] {
    model.searchMeetings(matching: query, filters: filters)
  }

  private var matchingTasks: [MemoraTask] {
    model.searchTasks(matching: query, filters: filters)
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
          Button("解除", systemImage: "xmark.circle") {
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
        symbol: "calendar",
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
        symbol: "person",
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
        title: model.spaces.first { $0.id == filters.spaceID }?.name ?? "プロジェクト",
        symbol: "folder",
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
        symbol: "checkmark.circle",
        isActive: filters.status != nil
      )
    }
    .accessibilityLabel("状態で絞り込む")
  }

  private func filterChip(title: String, symbol: String, isActive: Bool) -> some View {
    HStack(spacing: 4) {
      Image(systemName: symbol)
      Text(title)
      Image(systemName: "chevron.down")
        .font(.caption2.weight(.semibold))
    }
    .font(.subheadline.weight(.medium))
    .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
    .background(Color.primary.opacity(isActive ? 0.12 : 0.06), in: Capsule())
    .contentShape(Capsule())
  }

  private static let suggestions: [(title: String, symbol: String)] = [
    ("今週決まったことは？", "checkmark.seal"),
    ("未完了のタスクを教えて", "checkmark.square"),
    ("先週の会議を3行でまとめて", "text.alignleft")
  ]
}

