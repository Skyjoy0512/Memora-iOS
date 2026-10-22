"""Settings presentation contracts; UI tests separately exercise navigation and storage."""
from pathlib import Path
import re
import unittest

APP = Path(__file__).resolve().parents[2] / "App"


class SettingsPresentationChecks(unittest.TestCase):
    def test_root_contains_topics_not_leaf_preferences(self):
        root = (APP / "SettingsView.swift").read_text()
        self.assertIn("NavigationLink(value: category)", root)
        self.assertIn("ProfileEditorView()", root)
        self.assertNotIn("Toggle(", root)
        self.assertNotIn("SettingsPlanCard", root)
        self.assertNotIn("GmailSettingsView", root)
        self.assertFalse((APP / "SettingsPlanCard.swift").exists())

    def test_existing_preference_keys_and_permission_guards_remain(self):
        leaf = (APP / "SettingsCategoryView.swift").read_text()
        keys = set(re.findall(r'@AppStorage\("([^"]+)"\)', leaf))
        self.assertEqual(keys, {
            "memora.transcriptionEngine", "memora.transcriptionLanguage",
            "memora.autoLifeLog.enabled", "memora.journal.showCalendarEvents",
            "memora.appLock", "memora.prefersDarkAppearance", "memora.haptics.enabled",
        })
        for guard in ("AppLockService.availabilityMessage()", "discardPendingEnable()",
                      "CalendarService.requestAccess()", "model.deleteSampleContent()",
                      "model.signOut()", "model.deleteAccount()", "model.hasTeamPlan"):
            self.assertIn(guard, leaf)
        self.assertIn("課金されません", leaf)

    def test_service_routes_and_honest_availability_remain(self):
        services = (APP / "IntegrationsView.swift").read_text()
        detail = (APP / "IntegrationDetailView.swift").read_text()
        self.assertIn("IntegrationDetailView(service: service)", services)
        self.assertIn('service.isImplemented ? status(service.id) : "未対応"', services)
        for destination in ("GmailSettingsView()", "NotionSettingsView()", "MCPServersView()"):
            self.assertIn(destination, detail)
        self.assertIn("SkillsView()", (APP / "SettingsCategoryView.swift").read_text())
        self.assertNotIn("SkillsView()", services)

    def test_interface_icons_have_one_renderer_and_real_touch_labels(self):
        for name in ("SettingsIcon.swift", "ToolbarIconGlyph.swift"):
            source = (APP / name).read_text()
            for obsolete in ("ArtworkIcon", "glyphScale", "ScaledMetric", "searchIconSize"):
                self.assertNotIn(obsolete, source)
        self.assertIn("MemoraInterfaceIcon", (APP / "SettingsIcon.swift").read_text())
        self.assertIn("MemoraIconMetrics.glyph", (APP / "ToolbarIconGlyph.swift").read_text())
        self.assertIn("minHeight: MemoraIconMetrics.touchTarget", (APP / "SettingsLabel.swift").read_text())
        self.assertIn("MemoraInterfaceIcon(icon: symbol)", (APP / "FileSidebarView.swift").read_text())

    def test_workspace_and_sidebar_content_can_wrap_and_scroll(self):
        workspace = (APP / "WorkspaceSwitcher.swift").read_text()
        self.assertNotIn("lineLimit(1)", workspace)
        sidebar = (APP / "FileSidebarView.swift").read_text()
        self.assertNotIn("WorkspaceSwitcher(", sidebar)
        self.assertIn("WorkspaceSettingsView()", (APP / "SettingsCategoryView.swift").read_text())
        self.assertIn("WorkspaceSwitcher(", (APP / "WorkspaceSettingsView.swift").read_text())
        self.assertLess(sidebar.index('SidebarRow(title: "ライブラリ"'), sidebar.index('sidebarSection("コレクション")'))
        self.assertIn("SidebarAccountFooter(profile: model.profile", sidebar)
        footer = (APP / "SidebarAccountFooter.swift").read_text()
        self.assertIn('accessibilityLabel("Memora Plus、プランと利用状況")', footer)
        self.assertIn(".fixedSize(horizontal: false, vertical: true)", footer)
        self.assertIn("minHeight: MemoraSpacing.touchTarget", footer)
        self.assertIn("AnyLayout(VStackLayout(alignment: .leading", sidebar)


if __name__ == "__main__":
    unittest.main()
