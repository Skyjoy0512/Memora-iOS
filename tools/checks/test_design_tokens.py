"""Static token contracts and WCAG math, not a full-screen accessibility audit."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "App"


def luminance(value):
    channels = [(value >> shift & 255) / 255 for shift in (16, 8, 0)]
    channels = [v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in channels]
    return sum(a * b for a, b in zip(channels, (.2126, .7152, .0722)))


class DesignTokenChecks(unittest.TestCase):
    def test_text_and_status_contrast(self):
        palette = (APP / "MemoraPalette.swift").read_text()
        colors = {
            name: (int(light, 16), int(dark, 16))
            for name, light, dark in re.findall(
                r"static let (\w+) = adaptive\(light: 0x([A-F0-9]+), dark: 0x([A-F0-9]+)", palette)
        }
        for role in ("textPrimary", "textSecondary", "danger", "warning", "success"):
            for surface in ("background", "card", "selection", "elevated"):
                for appearance in (0, 1):
                    a, b = sorted((luminance(colors[role][appearance]), luminance(colors[surface][appearance])))
                    self.assertGreaterEqual((b + .05) / (a + .05), 4.5, (role, surface, appearance))

    def test_typography_scales_with_native_roles(self):
        typography = (APP / "MemoraTypography.swift").read_text()
        for role in ("display", "screenTitle", "sectionHeading", "body", "readingBody", "secondary", "caption", "metadata"):
            self.assertRegex(typography, rf"static let {role}: Font = \.")
        self.assertNotIn("system(size:", typography)
        self.assertIn("@ScaledMetric", (APP / "MarkdownBlockView.swift").read_text())
        self.assertIn("@ScaledMetric", (APP / "InlineMarkdownEditor.swift").read_text())

    def test_shared_reading_renderer(self):
        response = (APP / "AIResponseMarkdownBlock.swift").read_text()
        self.assertIn("MarkdownBlockView(block: block)", response)
        editor = (APP / "EditableMarkdownDocument.swift").read_text()
        self.assertIn("MarkdownTableView", editor)
        self.assertIn("MarkdownTableView", (ROOT / "App/MarkdownBlockView.swift").read_text())
        self.assertIn("MarkdownBlockView", editor)

    def test_retired_implementations_are_not_second_theme(self):
        for retired in ("GlassSegmentedPicker.swift", "GlassSegmentedControl.swift", "SettingsIconStyle.swift"):
            self.assertFalse((APP / retired).exists(), retired)
        config = json.loads((ROOT / "Project.json").read_text())
        self.assertEqual(config["packages"]["LucideSwift"]["exactVersion"], "0.9.11")
        self.assertIn('Image(icon:', (APP / "MemoraInterfaceIcon.swift").read_text())

    def test_root_navigation_and_native_capture_contracts(self):
        root = (APP / "RootTabView.swift").read_text()
        for contract in ('rootTab(.library)', 'rootTab(.home)', 'rootTab(.askAI)', 'RootTabBar(selection:'):
            self.assertIn(contract, root)
        tab_bar = (APP / "RootTabBar.swift").read_text()
        self.assertIn('isSelected ? .filled : .stroked', tab_bar)
        self.assertIn('.accessibilityLabel(tab.title)', tab_bar)
        self.assertNotIn('.glassEffect(', tab_bar)
        sidebar = (APP / "FileSidebarView.swift").read_text()
        for title in ("マーケットプレイス", "タスク", "資料", "人物"):
            self.assertIn(f'SidebarRow(title: "{title}"', sidebar)
        capture = (APP / "CaptureFloatingButtons.swift").read_text()
        for contract in ("Button(action: onOpenCaptureMenu)", ".fileImporter(", "menus.transition(.identity)", ".memoraGlass(in: Circle()"):
            self.assertIn(contract, capture)
        sheet = (APP / "CaptureMenuSheet.swift").read_text()
        self.assertNotIn("shortcuts", sheet)
        self.assertIn("[.recording, .importAudio, .onlineMeeting, .newNote]", sheet)
        self.assertNotIn("ScrollView(.horizontal)", sheet)
        self.assertNotIn(".xmarkCircle", sheet)
        self.assertIn(".presentationDragIndicator(.visible)", sheet)
        self.assertNotIn(".navigationTitle(", sheet)
        source = (APP / "QuickAIComposer.swift").read_text()
        self.assertIn("ComposerMentionToken.parse", source)
        self.assertIn("!snapshot.hasMarkedText", source)
        bar = (APP / "AIComposerBar.swift").read_text()
        self.assertIn("prompt: Text(placeholder)", bar)
        self.assertIn("selection: $textSelection", bar)


if __name__ == "__main__":
    unittest.main()
