"""Structural guards complement native iOS interaction and screenshot checks."""
from pathlib import Path
import unittest

APP = Path(__file__).resolve().parents[2] / "App"


class ChatSurfacePresentationChecks(unittest.TestCase):
    def test_native_field_keeps_identity_and_navigation_follows_interaction(self):
        bar = (APP / "AIComposerBar.swift").read_text()
        self.assertEqual(bar.count("TextField(placeholder"), 1)
        self.assertIn("selection: $textSelection", bar)
        self.assertIn("isConversation || isExpanded", bar)
        self.assertIn("isFieldFocused || speechInput.isListening", bar)
        self.assertIn(".onChange(of: isInteracting, initial: true)", bar)
        self.assertIn("interactionChanged?(interacting)", bar)
        self.assertIn("ComposerInputObserver", bar)
        quick = (APP / "QuickAIComposer.swift").read_text()
        self.assertIn("isConversation: model.selectedTab == .askAI && scope == .global", quick)
        self.assertIn("isComposing = interacting", quick)
        self.assertIn("!snapshot.hasMarkedText", quick)

    def test_header_is_flat_without_removing_actions(self):
        header = (APP / "AskAIHeader.swift").read_text()
        self.assertNotIn("memoraGlass", header)
        for action in ("onOpenSidebar", "onNewChat", "onHistory", "onSearch"):
            self.assertIn(action, header)
        self.assertIn("Image(icon: .chevronDown)", header)
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

    def test_conversation_width_does_not_collapse_when_keyboard_closes(self):
        root = (APP / "RootTabView.swift").read_text()
        self.assertIn("isComposing || model.selectedTab == .askAI ? width - MemoraSpacing.xxl", root)
        self.assertIn("MemoraSpacing.readingWidth)", root)
        self.assertNotIn(".id(composerScope)\n", root)
        native = (APP / "ProminentTabBar.swift").read_text()
        for contract in ("UISegmentedControl", ".buttonStyle(.glass)", "matchedTransitionSource", "navigationTransition(.zoom"):
            self.assertIn(contract, native)

    def test_sidebar_footer_shortens_secondary_copy_not_tap_targets(self):
        footer = (APP / "SidebarAccountFooter.swift").read_text()
        self.assertIn('Text("プラン")', footer)
        self.assertIn('Text("サインイン")', footer)
        self.assertIn('accessibilityLabel("Memora Plus、プランと利用状況")', footer)
        settings = footer.split("Button(action: onSettings) {")[1]
        self.assertIn(".frame(width: MemoraSpacing.touchTarget, height: MemoraSpacing.touchTarget)", settings)
        self.assertIn(".contentShape(Circle())", settings)


if __name__ == "__main__":
    unittest.main()
