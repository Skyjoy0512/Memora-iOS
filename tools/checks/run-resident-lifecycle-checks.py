#!/usr/bin/env python3
"""Production resident queue/run/settlement/notification methods; no network or OS jobs."""
from pathlib import Path
import os
import subprocess
import tempfile

os.chdir(Path(__file__).resolve().parents[2])
model = Path('App/MemoraModel.swift').read_text()
for start, end in [('var meetings:', 'var spaces:'), ('var tasks:', 'var lifeLogEntries:'),
                   ('var lifeLogEntries:', 'private(set) var lifeLogDays'), ('var people:', 'private var meetingIndex'),
                   ('var aiWorkspaceGeneration', 'var homePath:')]:
    assert 'invalidatePendingResidents()' in model[model.index(start):model.index(end)], start
for start, end in [('var isRestoring =', 'var recordingElapsed'), ('var isStoreProtected =', 'var registeredLLMs'),
                   ('var disabledIntegrationIDs:', 'var mcpServers:')]:
    assert 'invalidateResidentEnvironment()' in model[model.index(start):model.index(end)], start
assert 'residentDefinitionsDidChange(from: oldValue)' in model
with tempfile.TemporaryDirectory(prefix='memora-residents-', dir=os.environ.get('MEMORA_CHECK_ROOT')) as temporary:
    root = Path(temporary)
    production = root / 'ProductionResidents.swift'
    source = Path('App/MemoraModel+Residents.swift').read_text()
    for framework in ['BackgroundTasks', 'UIKit', 'UserNotifications']:
        source = source.replace('import ' + framework + '\n', '')
    production.write_text(source)
    binary = root / 'checks'
    subprocess.run(['swiftc', 'Shared/MemoraIcon.swift', 'App/ResidentAgent.swift', 'App/ResidentTrigger.swift',
                    'App/ResidentExecutionLimits.swift', 'App/ResidentRunRequest.swift', 'App/AgentTurn.swift',
                    'App/AgentToolCall.swift', 'App/AgentToolOutcome.swift', 'App/AIAnswerResult.swift',
                    'App/AIAnswerFailure.swift', str(production), 'tools/checks/ResidentLifecycleChecks.swift',
                    '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, env=dict(os.environ, SWIFT_BACKTRACE='enable=no'))
