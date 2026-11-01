#!/usr/bin/env python3
"""Exercise the production attachment-import method with isolated file/partition fixtures."""
from pathlib import Path
import os
import subprocess
import tempfile

os.chdir(Path(__file__).resolve().parents[2])
source = Path("App/MemoraModel+Import.swift").read_text()
method = source.split("  func importAIAttachment(", 1)[1].split("  func importAIPhoto(", 1)[0]
with tempfile.TemporaryDirectory(prefix="memora-attachment-import-", dir=os.environ.get("MEMORA_CHECK_ROOT")) as temporary:
    root = Path(temporary)
    extracted = root / "ProductionAttachmentImport.swift"
    extracted.write_text("import Foundation\nextension MemoraModel {\n  func importAIAttachment(" + method + "}\n")
    binary = root / "checks"
    subprocess.run(["swiftc", "App/AIAttachment.swift", "App/AIAttachmentFileReference.swift", str(extracted),
                    "tools/checks/AttachmentPartitionImportChecks.swift", "-o", str(binary)], check=True)
    subprocess.run([str(binary), str(root)], check=True)
