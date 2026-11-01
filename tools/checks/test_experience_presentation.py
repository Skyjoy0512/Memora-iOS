"""Presentation contracts supplement simulator interaction tests, not a visual audit."""
from pathlib import Path
import unittest

APP = Path(__file__).resolve().parents[2] / "App"


class ExperiencePresentationChecks(unittest.TestCase):
    def test_onboarding_is_honest_optional_and_scrolls_at_large_text(self):
        view = (APP / "OnboardingView.swift").read_text()
        copy = (APP / "OnboardingPage.swift").read_text()
        preview = (APP / "OnboardingPreview.swift").read_text()
        for contract in ("ScrollView {", 'Button("スキップ", action: skip)', 'Button(action: showSample)',
                         'Button("ログインせず始める", action: skip)', '"録音してみる"', "startRecording()", "OccupationSelectionView()"):
            self.assertIn(contract, view)
        for claim in ("設定も準備もいりません", "終わった瞬間", "担当と期限まで揃います"):
            self.assertNotIn(claim, copy)
        self.assertIn("初回のモデル取得や処理に時間がかかる", view)
        self.assertIn('.accessibilityIdentifier("onboarding.next")', view)
        actions = view.split("private var actions:")[1]
        self.assertIn("startRecording()", actions)
        self.assertNotIn("page.next", actions)
        self.assertIn("表示例・架空の会話", preview)
        self.assertNotIn("memoraCard", preview)
        self.assertNotIn("repeatForever", preview)
        self.assertIn(".accessibilityElement(children: .combine)", preview)
        entry = (APP / "ContentView.swift").read_text()
        self.assertIn("if model.openSummarizedAudioSample() { model.completeOnboarding() }", entry)
        self.assertNotIn("model.loadSampleContent()", entry)
        self.assertIn("既存の記録は変更していません", entry)

    def test_authentication_never_pretends_to_connect(self):
        auth = (APP / "AuthView.swift").read_text()
        provider = (APP / "AuthProviderButton.swift").read_text()
        for option in (".apple", ".google", ".email"):
            self.assertIn(f"AuthProviderButton(provider: {option})", auth)
        self.assertIn('Text("ログインせず利用").frame(maxWidth: .infinity)', auth)
        self.assertIn('Text("準備中")', provider)
        self.assertIn("認証は未接続です", provider)
        self.assertIn("許可した内容を送信します", auth)
        self.assertNotIn("model.signIn", auth)
        self.assertNotIn("SecureField", auth)

    def test_plans_separate_future_products_from_local_selection(self):
        plan = (APP / "PaywallView.swift").read_text()
        for contract in ('Text("提供予定のプラン")', 'Text("いま利用できること")', 'Picker("プラン", selection: $selectedPlan)',
                         ".pickerStyle(.menu)", "model.choosePlan(selectedPlan)", "LicenseActivationView()", "model.activeLicense != nil"):
            self.assertIn(contract, plan)
        for contract in ("有効な購入やサブスクリプションを示すものではありません", "クラウドAIが無制限になるプランではありません", "購入の復元について"):
            self.assertIn(contract, plan)
        self.assertNotIn("年額は月額の10か月分", plan)
        self.assertNotIn("BenefitRow", plan)
        self.assertNotIn("selectedPlan.tagline", plan)

    def test_one_empty_state_across_core_screens(self):
        self.assertFalse((APP / "ProjectWorkspaceEmptyState.swift").exists())
        for name in ("HomeView", "LibraryView", "ProjectsView", "SpaceDetailView", "TasksView", "PeopleView", "DocumentsView"):
            self.assertIn("MemoraEmptyState(", (APP / f"{name}.swift").read_text(), name)
        state = (APP / "MemoraEmptyState.swift").read_text()
        self.assertNotIn("memoraCard", state)
        self.assertIn("if let actionTitle, let action", state)
        self.assertIn("MemoraButtonStyle()", state)

    def test_flat_journal_and_real_date_reset(self):
        home = (APP / "HomeView.swift").read_text()
        self.assertIn('accessibilityLabel("今日に戻る")', home)
        self.assertIn("selectedDate = Calendar.current.startOfDay(for: .now)", home)
        self.assertIn(".disabled(isViewingToday)", home)
        self.assertIn("AnyLayout(VStackLayout", (APP / "HomeActivityLinks.swift").read_text())
        self.assertIn("JournalInsertionTime.suggestion(on: selectedDate)", home)
        self.assertIn("beginJournalEntry(after: index, in: timeline.items)", home)
        root = (APP / "RootTabView.swift").read_text()
        self.assertIn("LifeLogCreationSheet(date: model.lifeLogCreationDate ?? .now, eventDate: model.lifeLogCreationDate)", root)
        self.assertIn("onDismiss: { model.lifeLogCreationDate = nil }", root)
        empty = home.split("private var emptyDay:")[1].split("///")[0]
        self.assertNotIn("memoraCard", empty)
        self.assertNotIn("memoraCard", (APP / "HomeActivityLinks.swift").read_text())
        self.assertIn('MemoraSectionHeading(title: "タイムライン"', home)

    def test_search_states_are_scoped_and_clear_real_bindings(self):
        home = (APP / "HomeView.swift").read_text()
        search_branch = home.index("if isSearching {\n            searchResults(entries)\n          } else {")
        for operation in ("let ownTasks = model.ownTasks", "let markedDays = JournalActivityDays.build(", "let recap = JournalDailyRecap.build("):
            self.assertEqual(home.count(operation), 1)
            self.assertGreater(home.index(operation), search_branch)
        library = (APP / "LibraryView.swift").read_text()
        projects = (APP / "ProjectsView.swift").read_text()
        self.assertIn("isAwaitingQuery || statusFilter != .all ? [] : model.projectSources", library)
        self.assertIn("resultCount = count + savedSources.count", library)
        self.assertIn("@Binding var query: String", projects)
        self.assertIn("isAwaitingQuery || filter == .shared ? [] : projects", projects)
        self.assertIn("{ query = \"\" }", projects)

    def test_capture_keeps_execution_and_uses_system_menu(self):
        menu = (APP / "CaptureMenuPopover.swift").read_text()
        for call in ("onSelect(action)", "CaptureAction.available", "model.sourceAddProjectID = spaceID"):
            self.assertIn(call, menu)
        self.assertIn(".accessibilityHint(action.detail)", menu)
        native = (APP / "CaptureFloatingButtons.swift").read_text()
        for contract in ("group: .notes", "group: .recording", "Menu {", ".confirmationDialog(", "model.importInformationFile(url, context: context)", "NSUserCancelledError"):
            self.assertIn(contract, native)
        self.assertEqual(native.count("Menu {"), 2)
        self.assertIn(".opacity(isVisible ? 1 : 0)", native)
        self.assertIn("interactive: true, backed: false", native)
        notes = menu.split("case .notes:")[1].split("case .recording:")[0]
        self.assertLess(notes.index("action(.newMemo)"), notes.index("addSource"))
        recording = menu.split("case .recording:")[1].split("case .all:")[0]
        self.assertLess(recording.index("action(.recording)"), recording.index("action(.importAudio)"))
        self.assertLess(recording.index("action(.importAudio)"), recording.index("action(.onlineMeeting)"))
        self.assertLess(native.index("importContext = LocalImportContext"), native.index("isFileImporterPresented = true"))
        for obsolete in ("Task.sleep", "navigationTransition", "matchedTransitionSource", ".popover("):
            self.assertNotIn(obsolete, native + menu)
        dispatch = (APP / "MemoraModel+CaptureMenu.swift").read_text()
        for call in ("startCapture(spaceID: projectID)", "onlineMeetingCaptureSpaceID = projectID", "startNewAIChat()", "isLifeLogCreationPresented = true", "openCalling()"):
            self.assertIn(call, dispatch)
        root = (APP / "RootTabView.swift").read_text()
        self.assertIn("onDismiss: completeOnlineMeetingDismissal", root)
        self.assertIn("spaceID: spaceID, context: context)", root)
        self.assertNotIn("Task.sleep", root)
        self.assertIn("spaceID: model.visibleProjectID", root)
        self.assertIn("!isComposing, !isKeyboardVisible", root)

    def test_search_and_device_toolbar_reuse_real_model_state(self):
        sidebar = (APP / "FileSidebarView.swift").read_text()
        self.assertIn('SidebarRow(title: "検索"', sidebar)
        root = (APP / "RootTabView.swift").read_text()
        self.assertIn("closeSidebar { model.sidebarSearchRequest = UUID() }", root)
        for file in ("LibraryView.swift", "HomeView.swift", "ToolsView.swift", "SearchView.swift"):
            self.assertIn(".onChange(of: model.sidebarSearchRequest)", (APP / file).read_text())
        for file in ("LibraryView.swift", "HomeView.swift"):
            source = (APP / file).read_text()
            self.assertIn("RecorderStatusToolbarButton()", source)
            self.assertNotIn('ToolbarIconButton("検索"', source)
        detail = (APP / "MeetingDetailToolbarActions.swift").read_text()
        self.assertIn("ToolbarItemGroup", detail)
        for obsolete in ("Task.sleep", "isPlayRevealed", "isSeparated", "glassEffectID"):
            self.assertNotIn(obsolete, detail)
        connection = (APP / "OmiPairingManager.swift").read_text()
        for contract in ("RecorderBatteryState.serviceUUID", "RecorderBatteryState.characteristicUUID", "connectedPeripheral === peripheral", "batteryState.disconnected(from:", "central.cancelPeripheralConnection(peripheral)"):
            self.assertIn(contract, connection)

    def test_task_and_document_actions_are_real(self):
        tasks = (APP / "TasksView.swift").read_text()
        self.assertIn("model.isAddTaskPresented = true", tasks)
        self.assertIn("todayOnly = false", tasks)
        self.assertIn('ToolbarIconButton("元の会議を開く"', tasks)
        self.assertIn("sourceTitle", (APP / "TaskRow.swift").read_text())
        self.assertIn("model.openSystemDestination(.askAI)", (APP / "DocumentsView.swift").read_text())
        meeting = (APP / "MeetingDetailView.swift").read_text()
        self.assertIn("Text(meeting.displayTitle)", meeting)
        self.assertIn('joined(separator: " · ")', meeting)

    def test_source_editors_keep_drafts_and_own_their_save_errors(self):
        add = (APP / "ProjectSourceAddSheet.swift").read_text()
        edit = (APP / "ProjectNoteEditSheet.swift").read_text()
        self.assertIn('accessibilityIdentifier("source.content")', add)
        self.assertNotIn("右下の＋", add)
        for source in (add, edit):
            self.assertIn("presentsErrorsLocally: true", source)
            self.assertIn('.accessibilityLabel("タイトル")', source)
            self.assertIn(".title", source)
            self.assertIn("DraftStore.load", source)
            self.assertIn("DraftStore.clear", source)
        self.assertIn(".interactiveDismissDisabled(isSaving)", edit)

    def test_source_import_captures_context_before_native_pickers(self):
        add = (APP / "ProjectSourceAddSheet.swift").read_text()
        self.assertIn("fileContext = LocalImportContext", add)
        self.assertIn("photoContext = LocalImportContext", add)
        self.assertIn(".photosPicker(isPresented: $isSelectingPhotos", add)
        self.assertIn("importContext: context", add)
        self.assertIn("importProjectSource(title:", add)
        self.assertIn("context: context, presentsErrorsLocally: true", add)
        self.assertIn("defer { photos = [] }", add)
        self.assertNotIn(".onTapGesture", add)
        audio = (APP / "MemoraModel+Import.swift").read_text()
        self.assertIn("context.isCurrent(in: self, allowsRemovedProject: true)", audio)
        self.assertIn("return meeting.id", audio)
        self.assertIn("if await importInformationFile(url, context: context) != nil", audio)
        self.assertIn("removeInboxCopyIfNeeded(url)", audio)


if __name__ == "__main__":
    unittest.main()
