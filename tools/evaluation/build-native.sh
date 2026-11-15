#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ $# -ne 1 || -e "$1" || -e "$1.build.json" || -e "$1.inputs.json" ]]; then
  echo 'Pass a new executable path outside the repository' >&2
  exit 64
fi
source tools/checks/audio-diagnostic-sources.sh
python3 - "$1" <<'PY'
from pathlib import Path
import sys
import importlib.util
import json
root = Path.cwd().resolve()
target = Path(sys.argv[1]).resolve()
if target == root or root in target.parents:
    raise SystemExit('The executable must be outside the repository')
spec = importlib.util.spec_from_file_location('guard', root / 'tools/checks/run-quality-checks.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
Path(str(target) + '.inputs.json').write_text(json.dumps(module.source_snapshot()))
PY
swiftc -D MEMORA_SUMMARY_EVALUATION -enable-bare-slash-regex \
  Shared/MemoraIcon.swift App/SummaryProcessingMode.swift App/ReadabilityGuide.swift App/SummaryPrompt.swift \
  App/TranscriptSegment.swift App/SpeakerIdentificationStatus.swift App/MemoraFormat.swift \
  App/SummaryArtifactScope.swift App/MeetingSummaryInput.swift App/SummaryTemplate.swift App/SummaryMarketTemplate.swift \
  App/SummaryTemplateChoice.swift App/SummaryUseCase.swift App/VideoSummaryTemplate.swift App/SummarySensitivity.swift App/SummaryLength.swift \
  App/SummaryPreferences.swift App/SummaryTemplateCategory.swift App/SummaryTemplateCatalog.swift App/SummaryTemplateCatalog+Workflows.swift \
  App/OccupationSummaryTemplates.swift App/SummaryTemplateSelector.swift App/SummaryKnowledge.swift App/SummaryTopic.swift \
  App/SummaryRelation.swift App/SummaryRelationMarkdown.swift App/SummaryMarkdownBuilder.swift App/SummaryActionItem.swift \
  App/SummaryResponseParser.swift App/GeneratedSummaryEvidence.swift App/MeetingSummary.swift App/MarkdownSummaryExtractor.swift \
  "${audio_diagnostic_sources[@]}" App/SummaryNoteHierarchy.swift App/AIEngine.swift App/MemoraIntelligence.swift App/LLMSelection.swift \
  App/LLMProvider.swift App/LLMModelOption.swift App/AIAnswerFailure.swift App/AIAnswerResult.swift App/SummaryDiagnostics.swift \
  App/ModelCapabilities.swift App/ModelCapabilityRegistry.swift App/SummaryProviderAdapter.swift App/SummaryGenerationPolicy.swift \
  App/SummaryTokenBudget.swift App/SummaryInputPartition.swift App/SummaryPartScheduler.swift App/SummarySourceIndex.swift \
  App/SummaryRequestAdmission.swift App/SummaryRetryDelay.swift App/CloudHTTPTransport.swift App/LocalStore.swift \
  App/SummaryArtifactCache.swift App/SummaryArtifactIdentity.swift App/SummaryPartArtifact.swift App/SummaryCompositionPlan.swift \
  App/SummaryOptimizationGate.swift App/MeetingSummarizer+ParallelComposition.swift App/MeetingSummarizer.swift \
  App/CloudAIService.swift App/CloudSummaryResponse.swift App/CloudTurnStreaming.swift App/CloudTurnStreamReader.swift \
  App/CloudSSEEventDecoder.swift App/CloudStreamAccumulator.swift App/CloudAgentTurnDecoder.swift App/CloudTokenUsage.swift \
  App/AgentGenerationPolicy.swift App/AgentSessionBudget.swift App/AgentTurn.swift App/AgentToolCall.swift App/AIAnswerPrompt.swift \
  tools/evaluation/NativeSummaryEvaluation.swift tools/evaluation/NativeSummaryWire.swift \
  tools/evaluation/NativeSummaryServices.swift tools/evaluation/NativeSummarySnapshot.swift tools/evaluation/NativeSummaryDriver.swift -o "$1"
python3 - "$1" <<'PY'
from pathlib import Path
import sys, importlib.util, json, hashlib
target = Path(sys.argv[1]).resolve()
spec = importlib.util.spec_from_file_location('guard', Path('tools/checks/run-quality-checks.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
before = json.loads(Path(str(target) + '.inputs.json').read_text())
after = module.source_snapshot()
if before != after:
    raise SystemExit('Source changed during compilation; driver is invalid')
Path(str(target) + '.build.json').write_text(json.dumps({'sourceCodeSHA256': before['sha256'],
    'driverSHA256': hashlib.sha256(target.read_bytes()).hexdigest(), 'sourceGuardUnchanged': True,
    'compilerFlag': 'MEMORA_SUMMARY_EVALUATION', 'buildKind': 'development-host-only'}, indent=2) + '\n')
PY
