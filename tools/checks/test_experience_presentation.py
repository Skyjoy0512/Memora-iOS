"""Presentation contracts supplement simulator interaction tests, not a visual audit."""
from pathlib import Path
import unittest

APP = Path(__file__).resolve().parents[2] / "App"


class ExperiencePresentationChecks(unittest.TestCase):
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
        self.assertIn("isAwaitingQuery ? [] : model.projectSources", library)
        self.assertIn("resultCount = count + savedSources.count", library)
        self.assertIn("@Binding var query: String", projects)
        self.assertIn("isAwaitingQuery || filter == .shared ? [] : projects", projects)
        self.assertIn("{ query = \"\" }", projects)

    def test_capture_keeps_execution_and_uses_system_menu(self):
        menu = (APP / "CaptureMenuPopover.swift").read_text()
        for call in ("onSelect(action)", "CaptureAction.available", "model.sourceAddProjectID = spaceID"):
            self.assertIn(call, menu)
        self.assertIn(".accessibilityHint(action.detail)", menu)
        native = (APP / "CaptureToolbarButton.swift").read_text()
        for contract in ("ToolbarActionLabel", "Menu {", ".confirmationDialog(", "model.importPickedAudio(from: url, context: context)", "NSUserCancelledError"):
            self.assertIn(contract, native)
        self.assertLess(native.index("importContext = LocalImportContext"), native.index("isFileImporterPresented = true"))
        for obsolete in ("Task.sleep", "navigationTransition", "matchedTransitionSource", ".popover("):
            self.assertNotIn(obsolete, native + menu)
        dispatch = (APP / "MemoraModel+CaptureMenu.swift").read_text()
        for call in ("startCapture(spaceID: projectID)", "onlineMeetingCaptureSpaceID = projectID", "startNewAIChat()", "isLifeLogCreationPresented = true", "openCalling()"):
            self.assertIn(call, dispatch)

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
        self.assertIn("右上の＋", add)
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
        self.assertIn("fileImportContext = LocalImportContext", add)
        self.assertIn("photoImportContext = LocalImportContext", add)
        self.assertIn(".photosPicker(isPresented: $isSelectingPhotos", add)
        self.assertIn("importContext: context", add)
        self.assertIn("importProjectSource(title:", add)
        self.assertIn("context: context, presentsErrorsLocally: true", add)
        self.assertIn("defer { photos = [] }", add)
        self.assertNotIn(".onTapGesture", add)
        audio = (APP / "MemoraModel+Import.swift").read_text()
        self.assertIn("context.isCurrent(in: self, allowsRemovedProject: true)", audio)
        self.assertIn("return meeting.id", audio)
        self.assertEqual(audio.count("if await importAudio(from: url) != nil { removeInboxCopyIfNeeded(url) }"), 2)


if __name__ == "__main__":
    unittest.main()
