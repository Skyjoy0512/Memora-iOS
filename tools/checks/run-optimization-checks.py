#!/usr/bin/env python3
"""Isolated production-code checks; no credentials, network or app data."""
import os
from pathlib import Path
import subprocess
import tempfile

os.chdir(Path(__file__).resolve().parents[2])
subprocess.run(['python3', 'tools/checks/run-performance-checks.py'], check=True)
subprocess.run(['python3', 'tools/checks/run-local-store-checks.py'], check=True)
subprocess.run(['bash', 'tools/checks/run-tool-integration-checks.sh'], check=True)
project = ['ProjectCitation', 'ProjectEvidenceChunk', 'ProjectEvidenceInput', 'ProjectSourceText', 'ProjectContextBuilder']
checks = [
    ('ProjectSearchIndexChecks', project + ['ProjectSearchIndex'], []),
    ('ProjectContextChecks', ['ProjectCitation', 'ProjectEvidenceChunk', 'ProjectContextBuilder'], []),
    ('ProjectChatHistoryChecks', ['ProjectCitation', 'ProjectChatTurn', 'ProjectChatThread', 'ProjectChatHistory'], []),
    ('RecordStoreFailureChecks', ['RecordStore'], ['-DDEBUG']),
    ('HealthReviewLoaderChecks', ['HealthReviewSnapshot', 'HealthReviewLoader', 'ReviewPeriod'], []),
    ('JournalPerformanceChecks', ['TaskOwnership'], ['-O']),
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
