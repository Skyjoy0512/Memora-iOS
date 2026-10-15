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
tabs = (app / "ProminentTabBar.swift").read_text()
assert "UISegmentedControl" in tabs
assert "navigationTransition" in (app / "HomeView.swift").read_text()
assert "matchedTransitionSource" in (app / "HomeView.swift").read_text()
print("Motion policy passed: immediate saved content; native tab and journal Hero retained")
