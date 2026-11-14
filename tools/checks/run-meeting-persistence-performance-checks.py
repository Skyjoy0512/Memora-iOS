#!/usr/bin/env python3
"""Real Meeting codec and SQLite; isolated synthetic data, never the app store."""
import os
import argparse
from pathlib import Path
import subprocess
import tempfile

os.chdir(Path(__file__).resolve().parents[2])
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--counts', nargs='+', type=int, choices=[1000, 5000, 10000, 50000], default=[1000, 10000])
args = parser.parse_args()
names = ['Meeting', 'MeetingSource', 'MeetingStatus', 'RecordingMarker', 'TranscriptSegment',
         'RecordingAudioPart', 'RecordingAudioManifest',
         'SpeakerIdentificationStatus', 'RecordPrivacy', 'SummarySensitivity', 'SummaryKnowledge', 'TemplateSummary',
         'SummarySection', 'SummaryEvidence', 'SummaryEvidenceLink', 'GeneratedSummaryEvidence',
         'SummaryLength', 'SummaryPreferences', 'SummaryProcessingMode', 'LocalStore',
         'SummaryPreviewCache', 'MarkdownBlockParser', 'MarkdownBlock', 'SourcedMarkdownBlock', 'MarkdownFence']
with tempfile.TemporaryDirectory(prefix='memora-meeting-performance-', dir=os.environ.get('MEMORA_CHECK_TMPDIR')) as directory:
    binary = str(Path(directory) / 'meetings')
    subprocess.run(['swiftc', '-O', 'Shared/MemoraIcon.swift', *['App/' + name + '.swift' for name in names],
                    'tools/checks/MeetingPersistencePerformanceChecks.swift', '-o', binary], check=True)
    for count in args.counts:
        subprocess.run([binary, str(count), directory], check=True, timeout=240,
                       env={**os.environ, 'SWIFT_BACKTRACE': 'enable=no'})
