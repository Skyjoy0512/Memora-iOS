#!/usr/bin/env python3
"""Exercise the production OAuth browser lifecycle with held framework and transport callbacks."""
from pathlib import Path
import os
import subprocess
import tempfile

os.chdir(Path(__file__).resolve().parents[2])
source = Path("App/MCPOAuthBrowser.swift").read_text()
implementation = source[source.index("@MainActor"):]
with tempfile.TemporaryDirectory(prefix="memora-mcp-oauth-", dir=os.environ.get("MEMORA_CHECK_ROOT")) as directory:
    root = Path(directory)
    browser = root / "MCPOAuthBrowser.swift"
    browser.write_text("import Foundation\n" + implementation)
    binary = root / "checks"
    subprocess.run(["swiftc", "-swift-version", "6", str(browser), "App/MCPOAuthError.swift",
                    "tools/checks/MCPOAuthLifecycleChecks.swift", "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True, env=dict(os.environ, SWIFT_BACKTRACE="enable=no"), timeout=60)
