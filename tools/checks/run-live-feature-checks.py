"""Offline checks for the production Live boundary; never load a GGUF or send requests."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="memora-live-feature-", dir=os.environ.get("MEMORA_CHECK_ROOT")) as folder:
    scratch = Path(folder)
    for name, flags in [("release", []), ("debug", ["-DDEBUG"]),
                        ("release-opt", ["-DMEMORA_ENABLE_LIVE_CONVERSATION"]),
                        ("debug-opt", ["-DDEBUG", "-DMEMORA_ENABLE_LIVE_CONVERSATION"])]:
        binary = scratch / name
        subprocess.run(["swiftc", "-parse-as-library", *flags, str(ROOT / "App/FeatureFlags.swift"),
                        str(ROOT / "tools/checks/LiveFlagChecks.swift"), "-o", str(binary)], check=True)
        subprocess.run([str(binary)], check=True)
    files = ["FeatureFlags", "LocalVoiceLLM", "LocalVoiceModelStore", "LocalVoiceModelDownloadDelegate",
             "LocalVoicePrompt", "LocalTokenTextBuffer", "LiveVoiceError", "AIAnswerResult", "AIAnswerFailure"]
    for name, flags in [("release", []), ("debug", ["-DDEBUG"])]:
        binary = scratch / (name + "-disabled")
        subprocess.run(["swiftc", "-swift-version", "5", "-parse-as-library", *flags,
                        *[str(ROOT / "App" / (file + ".swift")) for file in files],
                        str(ROOT / "tools/checks/DisabledLiveChecks.swift"), "-o", str(binary)], check=True)
        subprocess.run([str(binary)], check=True)
print("Live feature checks: 4 compile configurations and 2 production-path refusal runs passed")
