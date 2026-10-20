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
        self.assertIn("entryCreationDate = isViewingToday ? .now : selectedDate", home)
        self.assertIn("LifeLogCreationSheet(date: entryCreationDate ?? .now)", home)
        self.assertIn("onDismiss: { entryCreationDate = nil }", home)
        empty = home.split("private var emptyDay:")[1].split("///")[0]
        self.assertNotIn("memoraCard", empty)
        self.assertNotIn("memoraCard", (APP / "HomeActivityLinks.swift").read_text())
        self.assertIn('MemoraSectionHeading(title: "タイムライン"', home)

    def test_search_states_are_scoped_and_clear_real_bindings(self):
        library = (APP / "LibraryView.swift").read_text()
        projects = (APP / "ProjectsView.swift").read_text()
        self.assertIn("isAwaitingQuery ? [] : model.projectSources", library)
        self.assertIn("resultCount = count + savedSources.count", library)
        self.assertIn("@Binding var query: String", projects)
        self.assertIn("isAwaitingQuery || filter == .shared ? [] : projects", projects)
        self.assertIn("{ query = \"\" }", projects)

    def test_capture_keeps_execution_and_native_morph(self):
        menu = (APP / "CaptureMenuPopover.swift").read_text()
        for call in ("select(action)", "model.startCapture(spaceID: destinationID)", "importSpaceID = destinationID", "handleAudioImport", "model.onlineMeetingCaptureSpaceID = destinationID"):
            self.assertIn(call, menu)
        self.assertIn("MemoraActionLabel", menu)
        self.assertIn(".accessibilityHint(action.detail)", menu)
        self.assertIn("min(contentHeight, 480)", menu)
        native = (APP / "ProminentTabBar.swift").read_text()
        for contract in ("UISegmentedControl", ".buttonStyle(.glass)", "matchedTransitionSource", "presentationCompactAdaptation(.popover)", "navigationTransition(.zoom"):
            self.assertIn(contract, native)

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


if __name__ == "__main__":
    unittest.main()
