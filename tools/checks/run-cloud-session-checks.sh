#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-cloud-session.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
# All URLSession instances use a fail-closed URLProtocol. Keychain, Gmail and
# credit display are isolated fixtures; no provider or token endpoint is reached.
swiftc -enable-bare-slash-regex -D PERSON_PROVENANCE_CHECKS -D ARTIFACT_PROVENANCE_CHECKS -D CLOUD_SESSION_CHECKS \
  App/SummaryProcessingMode.swift App/SummaryGenerationPolicy.swift App/SummaryDiagnostics.swift App/CloudAgentSession.swift App/CloudAIService.swift App/CloudSummaryResponse.swift App/CloudTurnStreaming.swift App/CloudTurnStreamReader.swift \
  App/CloudSSEEventDecoder.swift App/CloudStreamAccumulator.swift App/CloudAgentTurnDecoder.swift App/CloudTokenUsage.swift \
  App/AgentContextCompactor.swift App/AgentRunBudget.swift App/AgentSessionBudget.swift App/AgentOutputBudget.swift App/AgentGenerationPolicy.swift \
  App/LLMProvider.swift App/LLMSelection.swift App/LLMModelOption.swift App/ModelCapabilities.swift App/ModelBudgetScaling.swift App/TokenBudgetManager.swift App/AIAnswerPrompt.swift App/ReadabilityGuide.swift \
  App/AgentTool.swift App/AIToolRegistry.swift App/AIToolDefinition.swift App/IntegrationProvider.swift App/IntegrationToolResult.swift \
  App/MCPTool.swift App/MCPServerConfig.swift App/MCPOAuthSettings.swift \
  App/AIAnswerFailure.swift App/AIAnswerResult.swift App/AgentTurn.swift App/AgentRunEvent.swift App/AgentConversationLoop.swift \
  App/AnswerSourceCitation.swift App/AnswerCitations.swift App/MeetingLink.swift App/AIAnswerDocumentBuilder.swift \
  App/NativeAIInterface.swift App/NativeAIComponentStream.swift App/ToolInputValidator.swift App/MissingRecordNotice.swift App/MemoraModel+AnswerCitations.swift \
  Shared/MemoraIcon.swift App/LocalStore.swift App/Person.swift App/PersonIdentity.swift App/PersonAIContext.swift \
  App/MemoraModel+PersonPrivacy.swift App/PersonSelectionOption.swift App/PersonTaskAssociation.swift App/PersonMemory.swift App/PersonConversationSummary.swift \
  App/MemoraTask.swift App/TaskRelationships.swift App/TaskProgress.swift App/TaskOwnership.swift App/TaskHierarchy.swift \
  App/RecordPrivacy.swift App/RecordAccessPolicy.swift App/SummarySensitivity.swift App/RecordPrivacyTarget.swift \
  App/IdentifiableIndex.swift App/UndoAction.swift App/SummaryActionItem.swift App/AIPluginExecutionPolicy.swift \
  App/AgentToolCall.swift App/AgentToolOutcome.swift App/AgentStep.swift App/AIJournalPrivacy.swift App/LifeLogKind.swift App/LifeLogOrigin.swift \
  App/MemoraModel+People.swift App/MemoraModel+Tasks.swift App/MemoraModel+PersonScope.swift App/MemoraModel+PersonTools.swift \
  App/LifeLogEntry.swift App/LifeLogSource.swift App/TrashedLifeLogEntry.swift App/AIChatSource.swift App/AIChatScope.swift App/ReviewPeriod.swift App/AIRecordFingerprint.swift \
  App/MemoraModel+Journal.swift App/MemoraModel+JournalPeople.swift App/MemoraModel+RecordPrivacy.swift App/MemoraModel+AutomaticRecordTools.swift \
  tools/checks/PersonFixtureModel.swift App/ProjectCitation.swift App/AIAttachment.swift App/AIAttachmentFileReference.swift App/AIConversationEntry.swift App/AIEpisode.swift App/AIRecordReference.swift App/ArtifactProvenance.swift \
  App/ArtifactProjectSourceReference.swift App/AIConversationProvenance.swift App/AgentSourceReference.swift App/MemoraModel+Glossary.swift \
  App/AICalendarEventReference.swift App/AICalendarReadSnapshot.swift App/MemoraModel+CalendarContext.swift App/MemoraModel+AIProvenance.swift App/ProjectSource.swift App/MemoraDocumentKind.swift App/SlideArchetype.swift App/SlideContent.swift App/PresentationTheme.swift App/PresentationElement.swift App/PresentationText.swift App/TokenEstimate.swift App/PresentationEvidencePack.swift App/PresentationTypography.swift App/PresentationLayoutEngine.swift App/SlidePage.swift App/SlidePageLayout.swift App/PresentationValidator.swift App/PresentationExportCheck.swift App/PresentationOOXML.swift App/PresentationToolInput.swift App/DocumentSlide.swift App/PresentationPlan.swift App/DocumentArtifactRevision.swift App/MemoraDocument.swift App/MailDraft.swift \
  App/ArtifactSourceTarget.swift App/ArtifactSourceRow.swift App/MemoraModel+ArtifactProvenance.swift App/MemoraModel+Documents.swift \
  App/MemoraModel+MailDrafts.swift App/MemoraModel+MailDraftTool.swift \
  tools/checks/CloudSessionFixtureProtocol.swift tools/checks/CloudSessionFixtureResponse.swift tools/checks/CloudSessionFixtureServices.swift \
  tools/checks/SlowSummaryHTTPChecks.swift tools/checks/CloudSummaryTransportChecks.swift tools/checks/CloudSessionChecks.swift -o "$check_dir/session"
"$check_dir/session"
