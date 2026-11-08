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
assert 'CaptureMenuPopover' in capture
assert 'confirmationDialog' in capture
for obsolete in ('matchedTransitionSource', 'navigationTransition', 'Task.sleep', '.popover('):
    assert obsolete not in capture
assert 'if isVisible { menus.transition(.identity) }' in capture
assert "navigationTransition" in (app / "HomeView.swift").read_text()
assert "matchedTransitionSource" in (app / "HomeView.swift").read_text()

# Every animation that changes layout or journeys across a screen must be
# gated by Reduce Motion. Shared press feedback is brief and the continuous
# renderers pause themselves through their own `reduceMotion` checks.
press_styles = {"MemoraButtonStyle.swift", "MemoraMenuButtonStyle.swift", "MemoraQuietButtonStyle.swift"}
findings = []
for path in sorted(app.glob("*.swift")):
    if path.name == "MemoraMotion.swift":
        continue
    lines = path.read_text().splitlines()
    for index, line in enumerate(lines):
        if "withAnimation(" in line:
            window = "\n".join(lines[max(0, index - 8): index + 1])
            if "reduceMotion" not in window:
                findings.append(f"{path.name}:{index + 1} withAnimation without Reduce Motion")
        if ".animation(" in line and "TimelineView(.animation" not in line and path.name not in press_styles:
            if "reduceMotion" not in line:
                findings.append(f"{path.name}:{index + 1} .animation without Reduce Motion")
assert not findings, findings
assert "repeatForever" not in "".join(path.read_text() for path in app.glob("*.swift"))

print("Motion policy passed: bounded screen/text entrances; no per-row reveal; native capture menus and journal Hero retained; bottom tabs hidden; animations gated by Reduce Motion")
