#!/usr/bin/env python3
"""Isolated production-code checks; no credentials, network or app data."""
import os
from pathlib import Path
import subprocess
import tempfile

os.chdir(Path(__file__).resolve().parents[2])
subprocess.run(['python3', 'tools/checks/run-performance-checks.py'], check=True)
subprocess.run(['python3', '-B', 'tools/checks/run-audio-resource-checks.py'], check=True)
subprocess.run(['python3', '-B', 'tools/checks/test_process_resource_sampler.py'], check=True)
subprocess.run(['bash', 'tools/checks/run-recording-recovery-checks.sh'], check=True)
subprocess.run(['python3', 'tools/checks/run-local-store-checks.py'], check=True)
subprocess.run(['python3', 'tools/checks/run-location-persistence-checks.py'], check=True)
subprocess.run(['python3', 'tools/checks/run-webhook-lifecycle-checks.py'], check=True)
subprocess.run(['python3', 'tools/checks/run-cloud-share-lifecycle-checks.py'], check=True)
subprocess.run(['python3', 'tools/checks/run-resident-lifecycle-checks.py'], check=True)
subprocess.run(['python3', 'tools/checks/run-agent-outcome-checks.py'], check=True)
subprocess.run(['python3', 'tools/checks/run-meeting-persistence-performance-checks.py'], check=True)
subprocess.run(['bash', 'tools/checks/run-tool-integration-checks.sh'], check=True)
subprocess.run(['bash', 'tools/checks/run-license-persistence-checks.sh'], check=True)
project = ['ProjectCitation', 'ProjectEvidenceChunk', 'ProjectEvidenceInput', 'ProjectSourceText', 'ProjectContextBuilder']
checks = [
    ('RecordingResourceLifecycleChecks', ['RecordingPowerMode', 'MemoraModel+RecordingResources'], ['-swift-version', '6']),
    ('ProjectSearchIndexChecks', project + ['ProjectSearchIndex'], []),
    ('ProjectContextChecks', ['ProjectCitation', 'ProjectEvidenceChunk', 'ProjectContextBuilder'], []),
    ('ProjectChatHistoryChecks', ['ProjectCitation', 'ProjectChatTurn', 'ProjectChatThread', 'ProjectChatHistory'], []),
    ('RecordStoreFailureChecks', ['RecordStore', 'DraftStore', 'LocalSaveFailure'], ['-swift-version', '6', '-DDEBUG']),
    ('HealthReviewLoaderChecks', ['HealthReviewSnapshot', 'HealthReviewLoader', 'ReviewPeriod'], []),
    ('JournalPerformanceChecks', ['TaskOwnership', 'TaskRelationships'], ['-O']),
    ('JournalActivityDaysChecks', ['JournalActivityDays', 'TaskOwnership', 'MemoraTask', 'TaskRelationships', 'TaskProgress', 'RecordPrivacy', 'SummarySensitivity'], []),
    ('RecordPrivacyChecks', ['RecordPrivacy', 'RecordAccessPolicy', 'SummarySensitivity'], []),
    ('RootNavigationChecks', ['RootTab', 'RootNavigation', 'LibraryRoute', 'LibrarySection', 'AIQueryScope', 'MemoraArtwork'], []),
    ('ProjectSourceFilesChecks', ['ProjectSourceFiles'], []),
    ('SourceLookupChecks', ['IdentifiableIndex'], ['-O']),
    ('StandaloneRecordPrivacyChecks', ['RecordPrivacy', 'RecordAccessPolicy', 'SummarySensitivity', 'AIJournalPrivacy', 'LifeLogKind', 'LifeLogOrigin', 'MemoraTask', 'TaskRelationships', 'TaskProgress'], []),
]
with tempfile.TemporaryDirectory(prefix='memora-checks-', dir=os.environ.get('MEMORA_CHECK_TMPDIR')) as folder:
    for name, files, flags in checks:
        binary = str(Path(folder)/name)
        subprocess.run(['swiftc', *flags, *(['Shared/MemoraIcon.swift'] if 'LifeLogKind' in files or 'RootTab' in files else []), *[f'App/{f}.swift' for f in files], f'tools/checks/{name}.swift', '-o', binary], check=True)
        subprocess.run([binary], check=True)
    binary = str(Path(folder)/'ShareInboxChecks')
    subprocess.run(['swiftc', *[str(p) for p in Path('Shared/ShareInbox').glob('*.swift')], 'tools/checks/ShareInboxChecks.swift', '-o', binary], check=True)
    subprocess.run([binary], check=True)
print('Optimization checks: all passed')
