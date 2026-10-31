"""Keep interface glyphs consistent across SwiftUI, UIKit and widgets.

The debug runtime check verifies real rendered pixels. These checks guard the
source boundaries that compilation alone cannot enforce.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class LucideIconChecks(unittest.TestCase):
    def test_every_saved_identifier_has_a_documented_lucide_mapping(self):
        identifiers = re.findall(r'^  case (\w+) = "([^"]+)"',
                                 (ROOT / "Shared/MemoraIcon.swift").read_text(), re.M)
        mapping_source = (ROOT / "Shared/MemoraIcon+Lucide.swift").read_text()
        mappings = re.findall(r'^    case \.(\w+): \.(\w+)', mapping_source, re.M)
        self.assertEqual(len(identifiers), len(set(raw for _, raw in identifiers)))
        self.assertEqual(len(mappings), len(set(name for name, _ in mappings)))
        self.assertEqual({name for name, _ in identifiers}, {name for name, _ in mappings})
        self.assertNotRegex(mapping_source, r'\bdefault\s*:|LucideIconName\?')
        catalog = dict(mappings)
        documented = re.findall(r'^\| `([^`]+)` \| `([^`]+)` \|$',
                                (ROOT / "docs/LUCIDE_ICONS.md").read_text(), re.M)
        self.assertEqual(dict(documented), {raw: catalog[name] for name, raw in identifiers})

    def test_legacy_unmapped_identifiers_remain_readable(self):
        source = (ROOT / "Shared/MemoraIcon.swift").read_text()
        for name, raw in {
            "appleLogo": "apple.logo", "gCircle": "g.circle",
            "gobackward15": "gobackward.15", "goforward15": "goforward.15",
            "notionLogo": "notion.logo", "starBubble": "star.bubble",
            "textBadgePlus": "text.badge.plus", "trashSlash": "trash.slash",
        }.items():
            self.assertIn(f'case {name} = "{raw}"', source)

    def test_app_owned_images_do_not_bypass_lucide_or_use_symbol_only_effects(self):
        for folder in ("App", "Shared", "Widget Extension", "Share Extension"):
            for path in (ROOT / folder).rglob("*.swift"):
                source = re.sub(r'//[^\n]*', '', path.read_text())
                with self.subTest(path=path.relative_to(ROOT)):
                    if path.relative_to(ROOT).as_posix() == "App/AuthProviderButton.swift":
                        # The user's explicit brand request uses Apple's sign-in mark only.
                        self.assertIn('Image(systemName: "apple.logo")', source)
                        source = source.replace('Image(systemName: "apple.logo")', 'AppleSignInBrand()')
                    self.assertNotRegex(source, r'\b(?:Image|UIImage)\s*\(\s*systemName\s*:')
                    self.assertNotRegex(source, r'\bsystemImage\s*:')
                    self.assertNotRegex(source, r'\.symbolEffect\s*\(')
                    for match in re.finditer(r'Image\(icon:([^\n]+)\)\s*\n\s*\.font\(', source):
                        self.assertIn('size:', match.group(1),
                                      f'{path}: .font cannot resize a raster glyph')

    def test_editor_distinguishes_bullets_from_numbered_lists(self):
        editor = (ROOT / "App/MarkdownEditorField.swift").read_text()
        self.assertRegex(editor, r'icon: \.listBulletRectangle')
        self.assertRegex(editor, r'icon: \.listOrdered')
        self.assertIn('UIImage(icon:', editor)
        self.assertNotIn('preferredSymbolConfigurationForImage', editor)


if __name__ == "__main__":
    unittest.main()
