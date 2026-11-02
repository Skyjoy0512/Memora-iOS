#!/usr/bin/env python3
"""Run production recording admission across suspended service boundaries.

Microphone, session, persistence and UI are fixtures; no recording or AI use.
"""
from pathlib import Path
import os
import subprocess
import tempfile

os.chdir(Path(__file__).resolve().parents[2])
source = Path('App/MemoraModel+Capture.swift').read_text()
methods = source[source.index('  func startCapture('):source.index('  func retrySavingRecording()')]
with tempfile.TemporaryDirectory(prefix='memora-recording-start-', dir=os.environ.get('MEMORA_CHECK_ROOT')) as temporary:
    root = Path(temporary)
    production = root / 'RecordingStart.swift'
    production.write_text('import Foundation\nextension MemoraModel {\n' + methods + '}\n')
    binary = root / 'checks'
    subprocess.run(['swiftc', 'App/RecordingAudioPart.swift', 'App/RecordingAudioManifest.swift', 'Shared/MemoraIcon.swift', 'App/MemoraSpace.swift',
                    'App/LocalImportContext.swift', 'App/ProjectFiling.swift',
                    'tools/checks/RecordingStartChecks.swift', str(production),
                    '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
