"""Exercise the non-destructive onboarding path with production Meeting/SQLite."""
import os
from pathlib import Path
import subprocess
import tempfile

os.chdir(Path(__file__).resolve().parents[2])
names = ['RecordingAudioPart', 'RecordingAudioManifest', 'Meeting', 'MeetingSource', 'MeetingStatus', 'RecordingMarker', 'TranscriptSegment',
         'SpeakerIdentificationStatus', 'RecordPrivacy', 'SummarySensitivity', 'SummaryKnowledge', 'TemplateSummary',
         'SummarySection', 'SummaryEvidence', 'SummaryEvidenceLink', 'GeneratedSummaryEvidence',
         'SummaryLength', 'SummaryPreferences', 'SummaryProcessingMode', 'SummaryModeClassifier',
         'SummaryModeBreadcrumb', 'LocalStore',
         'SummaryPreviewCache', 'MarkdownBlockParser', 'MarkdownBlock', 'SourcedMarkdownBlock', 'MarkdownFence',
         'SummarizedAudioSample', 'MemoraModel+SamplePreview']
with tempfile.TemporaryDirectory(prefix='memora-sample-preview-', dir=os.environ.get('MEMORA_CHECK_TMPDIR')) as directory:
    binary = str(Path(directory) / 'preview')
    subprocess.run(['swiftc', 'Shared/MemoraIcon.swift', *['App/' + name + '.swift' for name in names],
                    'tools/checks/SamplePreviewChecks.swift', '-o', binary], check=True)
    subprocess.run([binary], check=True, env={**os.environ, 'TMPDIR': directory, 'SWIFT_BACKTRACE': 'enable=no'})
