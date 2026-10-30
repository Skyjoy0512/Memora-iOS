"""Structural guards supplement executed Swift queue/privacy and native UI tests."""
from pathlib import Path
import unittest

APP = Path(__file__).resolve().parents[2] / 'App'

class WaitingAudioPresentationChecks(unittest.TestCase):
    def test_only_text_waits_for_ai(self):
        status = (APP / 'ConversationStatusLine.swift').read_text()
        for obsolete in ['ThinkingGauge', 'ProgressView', 'Image(', 'Canvas', 'TimelineView']:
            self.assertNotIn(obsolete, status)
        self.assertIn('ElapsedText(since: since)', status)
        self.assertIn('since: startedAt', (APP / 'WorkingStatus.swift').read_text())
        self.assertIn('showsShimmer && !isWaiting', status)
        self.assertIn('AccessibilityNotification.Announcement(label)', status)
        shimmer = (APP / 'ShimmerText.swift').read_text()
        self.assertIn('isActive && !reduceMotion && scenePhase == .active', shimmer)
        self.assertNotIn('repeatForever', shimmer)
        self.assertIn('message.text.isEmpty || isWaiting', (APP / 'ThinkingTraceView.swift').read_text())
        self.assertNotIn('AskAIGlow(', (APP / 'SearchView.swift').read_text())
        self.assertIn('projectChatPartialAnswers', (APP / 'ProjectChatWaitingStatus.swift').read_text())

    def test_summary_uses_a_transient_instruction_not_a_checkbox(self):
        sheet = (APP / 'SummaryGenerationSheet.swift').read_text()
        self.assertNotIn('confirmsCloudDisclosure', sheet)
        self.assertNotIn('Toggle(', sheet)
        self.assertIn('configuration.llm.summaryDestination', sheet)
        self.assertIn('configuration: configuration', sheet)
        self.assertIn('SummarySubmissionIntent(', sheet)
        pending = (APP / 'MemoraModel+BackgroundSummary.swift').read_text()
        self.assertIn('if job.cloudDisclosureConfirmed', pending)
        self.assertNotIn('cloudDisclosureConfirmed: job.cloudDisclosureConfirmed', pending)

    def test_decorations_cannot_drive_capture_or_sample_offscreen(self):
        resources = (APP / 'MemoraModel+RecordingResources.swift').read_text()
        self.assertIn('recordingIsForeground && !conserves', resources)
        self.assertIn('levelTicker?.cancel()', resources)
        self.assertNotIn('recorder.stop()', resources)
        self.assertNotIn('recorder.pause()', resources)
        capture = (APP / 'CaptureSessionView.swift').read_text()
        self.assertNotIn('model.levelMeter.level', capture)
        self.assertIn('setRecordingMeterVisible(false)', capture)
        live = (APP / 'RealtimeTranscriptionService.swift').read_text()
        self.assertIn('.bufferingNewest(16)', live)
        self.assertIn('analyzer.cancelAndFinishNow()', live)
        self.assertIn('collect.result', live)
        self.assertNotIn('recorder.stop()', live)
        self.assertIn('LazyVStack', (APP / 'RealtimeTranscriptView.swift').read_text())

if __name__ == '__main__':
    unittest.main()
