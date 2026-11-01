"""Guard entry rendering without forbidding purposeful native transitions."""
from pathlib import Path

app = Path(__file__).resolve().parents[2] / "App"
motion = (app / "MemoraMotion.swift").read_text()
assert "accessibilityReduceMotion" in motion
assert "repeatForever" not in motion
assert "guard revealProgress < 1 else { return }" in motion
# Requested screen entrances are brief and do not animate every list row.
for name in ("MeetingRow.swift", "ProjectSourceRow.swift"):
    row = (app / name).read_text()
    assert ".memoraAppear(" not in row
    assert ".memoraTextReveal(" not in row
detail = (app / "MeetingDetailView.swift").read_text()
assert ".id(selectedSection)" not in detail
assert "sectionTransition" not in detail
root = (app / "RootTabView.swift").read_text()
assert 'toolbar(.hidden, for: .tabBar)' in root
assert 'onCloseAnimationCompleted: completeSidebarAction' in root
assert 'model.composerDismissRequests += 1' in root
capture = (app / "CaptureFloatingButtons.swift").read_text()
assert 'Menu {' in capture
assert 'confirmationDialog' in capture
for obsolete in ('matchedTransitionSource', 'navigationTransition', 'Task.sleep', '.popover('):
    assert obsolete not in capture
assert 'if isVisible {' in capture
assert "navigationTransition" in (app / "HomeView.swift").read_text()
assert "matchedTransitionSource" in (app / "HomeView.swift").read_text()
print("Motion policy passed: bounded screen/text entrances; no per-row reveal; native capture menus and journal Hero retained; bottom tabs hidden")
