#!/usr/bin/env python3
"""Real Meeting codec and SQLite; isolated synthetic data, never the app store."""
import os
from pathlib import Path
import subprocess
import tempfile

os.chdir(Path(__file__).resolve().parents[2])
names = ['Meeting', 'MeetingSource', 'MeetingStatus', 'RecordingMarker', 'TranscriptSegment',
         'SpeakerIdentificationStatus', 'RecordPrivacy', 'SummarySensitivity', 'TemplateSummary',
         'SummarySection', 'SummaryEvidence', 'SummaryEvidenceLink', 'GeneratedSummaryEvidence',
         'SummaryLength', 'SummaryPreferences', 'SummaryProcessingMode', 'LocalStore',
         'SummaryPreviewCache', 'MarkdownBlockParser', 'MarkdownBlock', 'SourcedMarkdownBlock', 'MarkdownFence']
with tempfile.TemporaryDirectory(prefix='memora-meeting-performance-', dir=os.environ.get('MEMORA_CHECK_TMPDIR')) as directory:
    binary = str(Path(directory) / 'meetings')
    subprocess.run(['swiftc', '-O', 'Shared/MemoraIcon.swift', *['App/' + name + '.swift' for name in names],
                    'tools/checks/MeetingPersistencePerformanceChecks.swift', '-o', binary], check=True)
    for count in [1000, 10000]:
        subprocess.run([binary, str(count), directory], check=True, timeout=240,
                       env={**os.environ, 'SWIFT_BACKTRACE': 'enable=no'})
