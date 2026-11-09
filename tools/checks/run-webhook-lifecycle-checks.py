#!/usr/bin/env python3
"""Actual webhook model methods plus bounded HTTP; all transport endpoints are fixtures."""
from pathlib import Path
import os
import subprocess
import tempfile

os.chdir(Path(__file__).resolve().parents[2])
model = Path('App/MemoraModel.swift').read_text()
for start, end in [('var meetings:', 'var spaces:'), ('var tasks:', 'var lifeLogEntries:'),
                   ('var webhookEndpoints:', 'var webhookResults:'), ('var currentTeamID:', 'var isTeamCreationPresented'),
                   ('var isRestoring =', 'var recordingElapsed'), ('var isStoreProtected =', 'var registeredLLMs')]:
    assert 'invalidatePendingWebhookDeliveries()' in model[model.index(start):model.index(end)], start
meetings = model[model.index('var meetings:'):model.index('var spaces:')]
tasks = model[model.index('var tasks:'):model.index('var lifeLogEntries:')]
assert meetings.index('meetingIndex.invalidate()') < meetings.index('invalidatePendingWebhookDeliveries()')
assert tasks.index('tasksByMeeting = nil') < tasks.index('invalidatePendingWebhookDeliveries()')
with tempfile.TemporaryDirectory(prefix='memora-webhooks-', dir=os.environ.get('MEMORA_CHECK_ROOT')) as temporary:
    root = Path(temporary)
    production = root / 'ProductionWebhookModel.swift'
    # Replace only the network boundary for deterministic in-flight state changes.
    production.write_text(Path('App/MemoraModel+Webhooks.swift').read_text().replace('WebhookDelivery.send(', 'WebhookTransportFixture.send('))
    binary = root / 'checks'
    subprocess.run(['swiftc', 'Shared/MemoraIcon.swift', 'App/Meeting.swift', 'App/MeetingSource.swift',
                    'App/MeetingStatus.swift', 'App/TranscriptSegment.swift', 'App/SpeakerIdentificationStatus.swift',
                    'App/RecordingMarker.swift', 'App/RecordingAudioPart.swift', 'App/RecordingAudioManifest.swift',
                    'App/MemoraTask.swift', 'App/TaskProgress.swift', 'App/TaskRelationships.swift',
                    'App/RecordPrivacy.swift', 'App/RecordAccessPolicy.swift', 'App/SummarySensitivity.swift',
                    'App/WebhookEndpoint.swift', 'App/WebhookDeliveryJob.swift', 'App/WebhookResult.swift',
                    'App/WebhookDelivery.swift', 'App/WebhookRedirectPolicy.swift', str(production),
                    'tools/checks/WebhookLifecycleChecks.swift', '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, env=dict(os.environ, SWIFT_BACKTRACE='enable=no'))
