"""Check that every notice in the shipped registry has its complete local resource."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
source = (root / "App/OpenSourceNotice.swift").read_text()
files = []
for block in re.findall(r'files:\s*\[([^\]]*)\]', source, re.S):
    files.extend(re.findall(r'"([^"\n]+)"', block))
assert len(files) >= 20, len(files)
for name in files:
    assert Path(name).name == name
    body = (root / "App/Resources" / name).read_text()
    assert len(body) > 300 and any(term in body for term in
        ("License", "license", "permission", "NOTICE", "SwiftLog", "Redistribution and use")), name
assert "オープンソースライセンス" in (root / "App/SettingsView.swift").read_text()
assert "Copyright (c) 2026 Carnot AI Inc." in (root / "App/Resources/ConsultingPPTX-LICENSE.txt").read_text()
print(f"OSS registry: {len(files)} referenced license/notice files present; complete MIT attribution retained")
