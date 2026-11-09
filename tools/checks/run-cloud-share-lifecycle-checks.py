#!/usr/bin/env python3
"""Production CloudKit preparation/rollback decisions with a suspended database fixture."""
from pathlib import Path
import os
import subprocess
import tempfile

os.chdir(Path(__file__).resolve().parents[2])
source = Path('App/MemoraModel+Backup.swift').read_text()
methods = source[source.index('  /// Shares a project'):source.index('  /// Restores a package')]
service = Path('App/CloudSharingService.swift').read_text()
methods_service = service[service.index('  func makeShare('):service.index('  /// Updates a snapshot')]
model = Path('App/MemoraModel.swift').read_text()
for start, end in [('var meetings:', 'var spaces:'), ('var tasks:', 'var lifeLogEntries:'),
                   ('var spaces:', 'var projectSources:'), ('var currentTeamID:', 'var isTeamCreationPresented'),
                   ('var isRestoring =', 'var recordingElapsed'), ('var isStoreProtected =', 'var registeredLLMs'),
                   ('var plan:', 'var hasTeamPlan')]:
    assert 'invalidatePendingCloudShare()' in model[model.index(start):model.index(end)], start
with tempfile.TemporaryDirectory(prefix='memora-cloud-share-', dir=os.environ.get('MEMORA_CHECK_ROOT')) as temporary:
    root = Path(temporary)
    production = root / 'ProductionCloudShare.swift'
    production.write_text('import Foundation\nimport CloudKit\nextension MemoraModel {\n' + methods +
                          '}\nextension CloudSharingService {\n' + methods_service + '}\n')
    binary = root / 'checks'
    subprocess.run(['swiftc', 'Shared/MemoraIcon.swift', 'App/Meeting.swift', 'App/MeetingSource.swift',
                    'App/MeetingStatus.swift', 'App/TranscriptSegment.swift', 'App/SpeakerIdentificationStatus.swift',
                    'App/RecordingMarker.swift', 'App/RecordingAudioPart.swift', 'App/RecordingAudioManifest.swift',
                    'App/MemoraTask.swift', 'App/TaskProgress.swift', 'App/TaskRelationships.swift',
                    'App/MemoraSpace.swift', 'App/TeamShareSnapshot.swift', 'App/CloudSharePreparation.swift',
                    'App/CloudSharingError.swift', 'App/TeamShareError.swift', 'App/RecordPrivacy.swift',
                    'App/RecordAccessPolicy.swift', 'App/SummarySensitivity.swift', str(production),
                    'tools/checks/CloudShareLifecycleChecks.swift', '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, env=dict(os.environ, SWIFT_BACKTRACE='enable=no'))
