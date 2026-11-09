#!/usr/bin/env python3
"""Run the production recorder checkpoint and failure path without a microphone."""
from pathlib import Path
import os
import subprocess
import tempfile

os.chdir(Path(__file__).resolve().parents[2])
source = Path('App/AudioRecorderService.swift').read_text()
failure = source[source.index('  private func handleUnexpectedStop('):source.index('  private func monitorStorage(')]
continuous_failure = source[source.index('  private func handleContinuousFailure('):source.index('  private func monitorContinuousStorage(')]
assert 'handleContinuousFailure(failure, runID: runID)' in source
checkpoint = source[source.index('  private func checkStorageAndDraft('):source.index('  private func observeSession(')]
with tempfile.TemporaryDirectory(prefix='memora-checkpoint-service-', dir=os.environ.get('MEMORA_CHECK_ROOT')) as temporary:
    root = Path(temporary)
    production = root / 'ProductionRecorderCheckpoint.swift'
    production.write_text('import Foundation\nextension RecordingCheckpointServiceFixture {\n' + failure + continuous_failure + checkpoint + '''
  func inputFailed(_ failure: RecordingMicrophoneInput.Failure, runID: UUID) {
    handleContinuousFailure(failure, runID: runID)
  }
  func tick(_ recorder: RecorderCheckpointRecorderFixture) async -> Bool {
    await checkStorageAndDraft(identity: ObjectIdentifier(recorder), directory: recorder.url.deletingLastPathComponent())
  }
}
''')
    environment = dict(os.environ, MEMORA_AUDIO_DIAGNOSTICS_DIRECTORY=str(root / 'diagnostics'), SWIFT_BACKTRACE='enable=no')
    diagnostics = subprocess.check_output(
        ['bash', '-c', r'source tools/checks/audio-diagnostic-sources.sh; printf "%s\n" "${audio_diagnostic_sources[@]}"'], text=True).splitlines()
    binary = root / 'checks'
    subprocess.run(['swiftc', '-D', 'MEMORA_HOST_CHECKS', *diagnostics,
                    'App/RecordingRunCoordinator.swift',
                    'tools/checks/RecordingRecoveryGate.swift', 'tools/checks/RecordingCheckpointServiceChecks.swift',
                    str(production), '-o', str(binary)], check=True, env=environment)
    subprocess.run([str(binary)], check=True, env=environment)
