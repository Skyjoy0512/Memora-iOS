#!/usr/bin/env python3
"""Execute production recording finalization and SQLite save/retry boundaries."""
from pathlib import Path
import os
import subprocess
import tempfile

os.chdir(Path(__file__).resolve().parents[2])
source = Path('App/MemoraModel+Capture.swift').read_text()
methods = source[source.index('  func retrySavingRecording()'):source.index('  func cancelCapture()')]
with tempfile.TemporaryDirectory(prefix='memora-recording-finalization-', dir=os.environ.get('MEMORA_CHECK_ROOT')) as temporary:
    root = Path(temporary)
    production = root / 'RecordingSaveCompletion.swift'
    production.write_text('import Foundation\nextension MemoraModel {\n' + methods + '}\n')
    environment = dict(os.environ, MEMORA_AUDIO_INBOX_DIRECTORY=str(root / 'Inbox'), SWIFT_BACKTRACE='enable=no',
                       MEMORA_AUDIO_DIAGNOSTICS_DIRECTORY=str(root / 'diagnostics'))
    sources = [
        'Shared/MemoraIcon.swift', 'App/LocalStore.swift', 'App/AudioInbox.swift',
        'App/MemoraSpace.swift', 'App/RecordPrivacy.swift', 'App/SummarySensitivity.swift',
        'App/RecordingAudioPart.swift', 'App/RecordingAudioManifest.swift', 'App/Meeting.swift', 'App/MeetingSource.swift', 'App/MeetingStatus.swift',
        'App/TranscriptSegment.swift', 'App/SpeakerIdentificationStatus.swift',
        'App/LifeLogEntry.swift', 'App/LifeLogKind.swift', 'App/LifeLogSource.swift', 'App/LifeLogOrigin.swift',
        'App/RecordingMarker.swift', 'App/RecordingAudioValidation.swift', 'App/ProjectFiling.swift',
        'App/RecordingDraftInspection.swift', 'App/MemoraModel+RecordingInspection.swift', 'App/MemoraModel+RecordingRecovery.swift', 'App/MemoraModel+RecordingCheckpoint.swift', 'App/MemoraModel+RecordingFinalization.swift',
        'tools/checks/AudioImportFixtureServices.swift', 'tools/checks/RecordingRecoveryStoreFixture.swift',
        'tools/checks/RecordingRecoveryFixtureModel.swift', 'tools/checks/RecordingRecoveryGate.swift',
        'tools/checks/RecordingFinalizationChecks.swift', 'tools/checks/RecordingManifestChecks.swift', str(production),
    ]
    # Keep the production diagnostics source list shared with the other checks.
    diagnostic_sources = subprocess.check_output(
        ['bash', '-c', r'source tools/checks/audio-diagnostic-sources.sh; printf "%s\n" "${audio_diagnostic_sources[@]}"'], text=True).splitlines()
    sources += diagnostic_sources
    binary = root / 'checks'
    subprocess.run(['swiftc', '-D', 'MEMORA_HOST_CHECKS', *sources, '-lsqlite3', '-o', str(binary)], check=True, env=environment)
    subprocess.run([str(binary), str(root)], check=True, env=environment)
    subprocess.run(['python3', '-B', 'tools/checks/audio-measurements.py', 'report', str(root / 'finalization-metrics.json')],
                   check=True, env=environment, stdout=subprocess.DEVNULL)
