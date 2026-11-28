#!/usr/bin/env python3
"""Check and measure the record row archive with production Swift and SQLite."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--counts", nargs="+", type=int, choices=[100, 1000, 10000, 50000],
                        default=[100, 1000, 10000, 50000])
    args = parser.parse_args()
    os.chdir(Path(__file__).resolve().parents[2])
    sources = [
        "LocalStore", "Meeting", "MeetingSource", "MeetingStatus", "RecordingMarker", "TranscriptSegment",
        "RecordingAudioPart", "RecordingAudioManifest", "SpeakerIdentificationStatus", "RecordPrivacy",
        "SummarySensitivity", "SummaryKnowledge", "SummaryModeClassifier", "SummaryModeBreadcrumb",
        "TemplateSummary", "SummarySection", "SummaryEvidence", "SummaryEvidenceLink",
        "GeneratedSummaryEvidence", "SummaryLength", "SummaryPreferences", "SummaryProcessingMode",
        "SummaryPreviewCache", "MarkdownBlockParser", "MarkdownBlock", "SourcedMarkdownBlock", "MarkdownFence",
        "MeetingRowStaging", "MeetingArchive",
    ]
    check_root = os.environ.get("MEMORA_CHECK_TMPDIR") or os.environ.get("MEMORA_CHECK_ROOT")
    with tempfile.TemporaryDirectory(prefix="memora-meeting-archive-", dir=check_root) as directory:
        binary = str(Path(directory) / "meeting-archive")
        subprocess.run(["swiftc", "-O", "Shared/MemoraIcon.swift", *[f"App/{name}.swift" for name in sources],
                        "tools/checks/MeetingArchiveChecks.swift",
                        "-lsqlite3", "-o", binary], check=True, timeout=300)
        for scenario in ["contract", *map(str, args.counts)]:
            subprocess.run([binary, directory, scenario], check=True, timeout=600,
                           env={**os.environ, "SWIFT_BACKTRACE": "enable=no"})


if __name__ == "__main__":
    main()
