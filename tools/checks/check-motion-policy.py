"""Guard entry rendering without forbidding purposeful native transitions."""
from pathlib import Path

app = Path(__file__).resolve().parents[2] / "App"
for path in app.glob("*.swift"):
    if path.name != "MemoraMotion.swift":
        assert ".memoraAppear(" not in path.read_text(), path
        assert ".memoraTextReveal(" not in path.read_text(), path
detail = (app / "MeetingDetailView.swift").read_text()
assert ".id(selectedSection)" not in detail
assert "sectionTransition" not in detail
root = (app / "RootTabView.swift").read_text()
assert 'toolbar(.hidden, for: .tabBar)' in root
assert 'onCloseAnimationCompleted: completeSidebarAction' in root
assert 'model.composerDismissRequests += 1' in root
capture = (app / "CaptureToolbarButton.swift").read_text()
assert 'Menu {' in capture
assert 'confirmationDialog' in capture
for obsolete in ('matchedTransitionSource', 'navigationTransition', 'Task.sleep', '.popover('):
    assert obsolete not in capture
assert 'model.selectedTab == tab && !model.isToolsPresented' in capture
assert "navigationTransition" in (app / "HomeView.swift").read_text()
assert "matchedTransitionSource" in (app / "HomeView.swift").read_text()
print("Motion policy passed: immediate saved content; sidebar completion, scoped system capture Menu/dialog and journal Hero retained; bottom tabs hidden")
