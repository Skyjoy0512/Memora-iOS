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
            for surface in ("background", "card"):
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
        self.assertIn("MarkdownTableRow", editor)
        self.assertIn("MarkdownBlockView", editor)

    def test_retired_implementations_are_not_second_theme(self):
        for retired in ("GlassSegmentedPicker.swift", "GlassSegmentedControl.swift", "SettingsIconStyle.swift"):
            self.assertFalse((APP / retired).exists(), retired)
        config = json.loads((ROOT / "Project.json").read_text())
        self.assertEqual(config["packages"]["LucideSwift"]["exactVersion"], "0.9.11")
        self.assertIn('Image(icon:', (APP / "MemoraInterfaceIcon.swift").read_text())

    def test_navigation_and_capture_contracts_remain_native(self):
        root = (APP / "RootTabView.swift").read_text()
        self.assertIn('toolbar(.hidden, for: .tabBar)', root)
        sidebar = (APP / "FileSidebarView.swift").read_text()
        for title in ("ライブラリ", "ジャーナル", "Ask AI", "マーケットプレイス"):
            self.assertIn(f'SidebarRow(title: "{title}"', sidebar)
        capture = (APP / "CaptureToolbarButton.swift").read_text()
        for contract in ("ToolbarActionLabel", "Menu {", "CaptureMenuPopover(spaceID: spaceID, onSelect: select)"):
            self.assertIn(contract, capture)
        source = (APP / "QuickAIComposer.swift").read_text()
        self.assertIn("ComposerMentionToken.parse", source)
        self.assertIn("!snapshot.hasMarkedText", source)
        bar = (APP / "AIComposerBar.swift").read_text()
        self.assertIn("TextField(placeholder", bar)
        self.assertIn("selection: $textSelection", bar)


if __name__ == "__main__":
    unittest.main()
