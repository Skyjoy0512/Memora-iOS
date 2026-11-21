"""Structural guards complement native iOS interaction and screenshot checks."""
from pathlib import Path
import unittest

APP = Path(__file__).resolve().parents[2] / "App"


class ChatSurfacePresentationChecks(unittest.TestCase):
    def test_native_field_keeps_identity_and_navigation_follows_interaction(self):
        bar = (APP / "AIComposerBar.swift").read_text()
        self.assertEqual(bar.count("TextField("), 1)
        self.assertIn("prompt: Text(placeholder)", bar)
        self.assertIn("selection: $textSelection", bar)
        self.assertIn("private var usesStackedLayout: Bool { isExpanded }", bar)
        self.assertIn("isFieldFocused || speechInput.isListening", bar)
        self.assertIn(".onChange(of: isInteracting, initial: true)", bar)
        self.assertIn("interactionChanged?(interacting)", bar)
        self.assertIn("ComposerInputObserver", bar)
        quick = (APP / "QuickAIComposer.swift").read_text()
        self.assertIn("isConversation: model.selectedTab == .askAI && scope == .global", quick)
        self.assertIn("isComposing = interacting", quick)
        self.assertIn("!snapshot.hasMarkedText", quick)

    def test_header_reserves_glass_for_controls_without_removing_actions(self):
        header = (APP / "AskAIHeader.swift").read_text()
        self.assertEqual(header.count(".memoraGlass("), 1)
        self.assertIn(".buttonStyle(MemoraQuietButtonStyle())", header)
        for action in ("onOpenSidebar", "onNewChat", "onHistory", "onSearch"):
            self.assertIn(action, header)
        self.assertIn("Image(icon: .chevronDown, size: MemoraIconMetrics.accessory)", header)
        self.assertIn(".disabled(model.aiMessages.isEmpty)", header)

    def test_response_actions_have_consistent_glyphs_and_reflow(self):
        bar = (APP / "AIResponseActionBar.swift").read_text()
        self.assertIn(".system(size: MemoraIconMetrics.glyph, weight: .regular)", bar)
        row = (APP / "AIReplyActionsRow.swift").read_text()
        self.assertIn("AnyLayout(VStackLayout", row)
        self.assertIn("minHeight: MemoraSpacing.touchTarget", row)
        self.assertIn("if excerptCount > 0", row)
        self.assertIn("AIAnswerActions(message: message)", row)
        self.assertIn("toggleSources", row)

    def test_composer_keeps_identity_while_capture_controls_yield_to_input(self):
        root = (APP / "RootTabView.swift").read_text()
        self.assertIn(".frame(maxWidth: MemoraSpacing.readingWidth)", root)
        self.assertIn(".padding(.trailing, showsCaptureButtons ? 60 : 0)", root)
        self.assertIn(".overlay(alignment: .bottomTrailing)", root)
        self.assertIn("compactIdle: true", root)
        self.assertNotIn(".id(composerScope)\n", root)
        native = (APP / "CaptureFloatingButtons.swift").read_text()
        for contract in ("Button(action: onOpenCaptureMenu)", ".fileImporter(", "menus.transition(.identity)", ".confirmationDialog(", "importInformationFile"):
            self.assertIn(contract, native)
        sheet = (APP / "CaptureMenuSheet.swift").read_text()
        self.assertIn("[.recording, .importAudio, .onlineMeeting, .newNote]", sheet)

    def test_sidebar_footer_keeps_settings_tap_target(self):
        footer = (APP / "SidebarAccountFooter.swift").read_text()
        self.assertNotIn("Divider()", footer)
        header = (APP / "SidebarHeaderView.swift").read_text()
        self.assertNotIn("Menu {", header)
        settings_root = (APP / "SettingsCategory.swift").read_text()
        self.assertIn("case account", settings_root)
        self.assertIn('case .plan: "プランと利用状況"', settings_root)
        settings = footer.split("Button(action: onSettings) {")[1]
        self.assertIn(".frame(width: MemoraSpacing.touchTarget, height: MemoraSpacing.touchTarget)", settings)
        self.assertIn(".contentShape(Circle())", settings)

    def test_attachment_plus_is_plain_without_changing_its_presentation(self):
        attachment = (APP / "AIComposerAttachmentButton.swift").read_text()
        self.assertNotIn(".glass", attachment)
        self.assertIn(".buttonStyle(.plain)", attachment)
        for contract in ("MemoraSpacing.touchTarget", "Menu {", "onSelect(action)"):
            self.assertIn(contract, attachment)
        for obsolete in ("navigationTransition", "matchedTransitionSource", "Task.sleep", ".popover("):
            self.assertNotIn(obsolete, attachment)

    def test_agent_suggestions_stage_only_revalidated_requests(self):
        source = (APP / "MemoraModel+AgentSuggestions.swift").read_text()
        for contract in ("currentTeamID == nil", "aiPersonScopeID == nil", "!isRestoring", "!isStoreProtected",
                         "allowsRecordAccess($0.id, purpose: .cloudAI)", "allowsTaskAccess($0, purpose: .cloudAI)",
                         "!SampleContent.isSample", "agentPromptSuggestions.contains(suggestion)", "composerDraft.isEmpty",
                         "composerAttachment == nil", "composerFocusRequest = UUID()"):
            self.assertIn(contract, source)
        self.assertNotIn("sendAIChat(", source)
        self.assertNotIn("Task {", source)

    def test_workspace_selection_and_recorder_paths_are_direct_and_honest(self):
        workspace = (APP / "WorkspaceSwitcher.swift").read_text()
        self.assertNotIn("Menu {", workspace)
        self.assertIn("model.selectWorkspace(workspace)", workspace)
        row = (APP / "WorkspaceSelectionRow.swift").read_text()
        for contract in (".checkmark", ".isSelected", "MemoraSpacing.touchTarget"):
            self.assertIn(contract, row)
        self.assertIn("ExternalRecorderSettingsView()", (APP / "RootTabView.swift").read_text())
        importer = (APP / "RecorderAudioImportView.swift").read_text()
        for contract in ("LocalImportContext(in: model)", "importInformationFile(url, context: context)",
                         "context.isCurrent(in: model)", 'value: "未対応"', "showsFailure = true"):
            self.assertIn(contract, importer)


if __name__ == "__main__":
    unittest.main()
