#!/usr/bin/env python3
"""Run the performance-contract checks: signal math, the record archive and the
voice activity model, each against production sources."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]

MEETING_SOURCES = [
    "LocalStore", "Meeting", "MeetingSource", "MeetingStatus", "RecordingMarker", "TranscriptSegment",
    "RecordingAudioPart", "RecordingAudioManifest", "SpeakerIdentificationStatus", "RecordPrivacy",
    "SummarySensitivity", "SummaryKnowledge", "SummaryModeClassifier", "SummaryModeBreadcrumb",
    "TemplateSummary", "SummarySection", "SummaryEvidence", "SummaryEvidenceLink",
    "GeneratedSummaryEvidence", "SummaryLength", "SummaryPreferences", "SummaryProcessingMode",
    "SummaryPreviewCache", "MarkdownBlockParser", "MarkdownBlock", "SourcedMarkdownBlock", "MarkdownFence",
    "MeetingRowStaging", "MeetingArchive",
]


def build(directory, name, sources, check, frameworks=(), shared=()):
    binary = str(Path(directory) / name)
    command = ["swiftc", "-O", *[f"Shared/{source}.swift" for source in shared],
               *[f"App/{source}.swift" for source in sources],
               f"tools/checks/{check}.swift", "-o", binary]
    for framework in frameworks:
        command += ["-framework", framework]
    subprocess.run(command, check=True, timeout=420, cwd=ROOT)
    return binary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive-counts", nargs="+", type=int, choices=[100, 1000],
                        default=[100, 1000])
    args = parser.parse_args()
    check_root = os.environ.get("MEMORA_CHECK_TMPDIR") or os.environ.get("MEMORA_CHECK_ROOT")
    with tempfile.TemporaryDirectory(prefix="memora-performance-contracts-", dir=check_root) as directory:
        level = build(directory, "audio-level", ["AudioLevelMath"], "AudioLevelMathChecks")
        subprocess.run([level], check=True, timeout=300, cwd=ROOT,
                       env={**os.environ, "SWIFT_BACKTRACE": "enable=no"})

        archive = build(directory, "meeting-archive", MEETING_SOURCES, "MeetingArchiveChecks",
                        shared=("MemoraIcon",))
        for scenario in ["contract", *map(str, args.archive_counts)]:
            subprocess.run([archive, directory, scenario], check=True, timeout=900, cwd=ROOT,
                           env={**os.environ, "SWIFT_BACKTRACE": "enable=no"})

        summary = build(directory, "summary-part-mapping",
                        ["TranscriptSegment", "SpeakerIdentificationStatus", "SummarySourceIndex",
                         "MemoraFormat", "RecordPrivacy", "SummarySensitivity"],
                        "SummaryPartMappingChecks")
        subprocess.run([summary], check=True, timeout=300, cwd=ROOT,
                       env={**os.environ, "SWIFT_BACKTRACE": "enable=no"})

        voice = build(directory, "voice-activity", ["VoiceActivityModelAssets"],
                      "VoiceActivityModelChecks", frameworks=("CoreML",))
        subprocess.run([voice], check=True, timeout=600, cwd=ROOT,
                       env={**os.environ, "SWIFT_BACKTRACE": "enable=no"})


if __name__ == "__main__":
    main()
