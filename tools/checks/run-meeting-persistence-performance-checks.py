#!/usr/bin/env python3
"""Real Meeting codec and SQLite; isolated synthetic data, never the app store."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

os.chdir(Path(__file__).resolve().parents[2])
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--counts', nargs='+', type=int, choices=[100, 1000, 5000, 10000, 50000], default=[100, 1000, 10000])
parser.add_argument('--segments-per-record', type=int, choices=[0, 20], default=20,
                    help='Separate record metadata from transcript payloads; neither run opens media files.')
parser.add_argument('--samples', type=int, choices=range(3, 22, 2), default=21, metavar='ODD_COUNT',
                    help='Write samples per record count, from 3 to 21.')
parser.add_argument('--store-revision', help='Compile LocalStore from this Git revision for comparison.')
args = parser.parse_args()
names = ['Meeting', 'MeetingSource', 'MeetingStatus', 'RecordingMarker', 'TranscriptSegment',
         'RecordingAudioPart', 'RecordingAudioManifest',
         'SpeakerIdentificationStatus', 'RecordPrivacy', 'SummarySensitivity', 'SummaryKnowledge', 'SummaryModeClassifier',
         'SummaryModeBreadcrumb', 'TemplateSummary',
         'SummarySection', 'SummaryEvidence', 'SummaryEvidenceLink', 'GeneratedSummaryEvidence',
         'SummaryLength', 'SummaryPreferences', 'SummaryProcessingMode',
         'SummaryPreviewCache', 'MarkdownBlockParser', 'MarkdownBlock', 'SourcedMarkdownBlock', 'MarkdownFence']
with tempfile.TemporaryDirectory(prefix='memora-meeting-performance-', dir=os.environ.get('MEMORA_CHECK_TMPDIR')) as directory:
    binary = str(Path(directory) / 'meetings')
    local_store = Path('App/LocalStore.swift')
    if args.store_revision:
        revision = subprocess.check_output(['git', 'rev-parse', '--verify', '--end-of-options',
                                            f'{args.store_revision}^{{commit}}'], text=True).strip()
        local_store = Path(directory) / local_store.name
        local_store.write_bytes(subprocess.check_output(['git', 'show', f'{revision}:App/LocalStore.swift']))
    subprocess.run(['swiftc', '-O', 'Shared/MemoraIcon.swift', *['App/' + name + '.swift' for name in names],
                    str(local_store), 'tools/checks/MeetingPersistencePerformanceChecks.swift', '-o', binary], check=True)
    for count in args.counts:
        subprocess.run([binary, str(count), directory, str(args.segments_per_record), str(args.samples)],
                       check=True, timeout=240,
                       env={**os.environ, 'SWIFT_BACKTRACE': 'enable=no'})
