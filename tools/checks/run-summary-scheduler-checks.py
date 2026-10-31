#!/usr/bin/env python3
"""Link the production OS scheduler against a deterministic UIKit/BackgroundTasks boundary."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="memora-summary-scheduler-") as temporary:
    directory = Path(temporary)
    source = (root / "App/SystemSummaryBackgroundScheduler.swift").read_text()
    source = "import Foundation\n" + "\n".join(line for line in source.splitlines()
                                            if line not in {"import BackgroundTasks", "import UIKit"})
    scheduler = directory / "SystemSummaryBackgroundScheduler.swift"
    scheduler.write_text(source)
    executable = directory / "check"
    subprocess.run(["swiftc", "App/SummaryDiagnostics.swift", "App/AIAnswerFailure.swift",
                    "App/SummaryBackgroundScheduling.swift",
                    str(scheduler), "tools/checks/ContinuedSummarySchedulerChecks.swift", "-o", str(executable)],
                   cwd=root, check=True)
    subprocess.run([str(executable)], cwd=root, check=True)
