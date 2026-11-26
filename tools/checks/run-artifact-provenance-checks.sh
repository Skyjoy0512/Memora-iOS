#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-artifact-provenance.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
entrypoint=tools/checks/ArtifactProvenanceChecks.swift
extra_sources=(-D ARTIFACT_PROVENANCE_CHECKS)
if [[ "${1:-}" == "--interface-task-execution" || "${1:-}" == "--calendar-interface" || "${1:-}" == "--task-proposals" ]]; then
  entrypoint=tools/checks/IntelligentUITaskExecutionChecks.swift
  if [[ "${1:-}" == "--calendar-interface" ]]; then entrypoint=tools/checks/CalendarInterfaceChecks.swift; fi
  if [[ "${1:-}" == "--task-proposals" ]]; then entrypoint=tools/checks/TaskProposalExecutionChecks.swift; fi
  extra_sources+=(-D INTERFACE_TASK_EXECUTION_CHECKS -D CLOUD_SESSION_CHECKS
    App/MCPServerConfig.swift App/MCPOAuthSettings.swift App/MCPTool.swift
    App/AgentTool.swift App/AIToolRegistry.swift App/AIToolDefinition.swift App/IntegrationProvider.swift App/IntegrationToolResult.swift
    App/AgentApproval.swift App/AgentTaskDraft.swift App/AgentInteractionWaiter.swift App/MemoraModel+AgentApproval.swift App/MemoraModel+TaskAgent.swift App/MemoraModel+TaskProposals.swift App/MemoraModel+CalendarTools.swift App/MemoraModel+IntegrationSettings.swift
    App/AgentConversationExecutionContext.swift App/CalendarAgentReadContext.swift
    tools/checks/CloudSessionFixtureServices.swift)
elif [[ -n "${1:-}" ]]; then
  exit 64
fi
swiftc App/SummaryKnowledge.swift App/SourceSummaryOptions.swift App/SummaryLength.swift App/SummaryEngineChoice.swift App/AIAttachmentCitation.swift App/AIAnswerFailure.swift App/AIAnswerResult.swift App/AgentTurn.swift App/AgentRunEvent.swift App/AgentConversationLoop.swift App/AnswerSourceCitation.swift App/AnswerCitations.swift App/MeetingLink.swift App/AIAnswerDocumentBuilder.swift App/NativeAIInterface.swift App/JSONRenderPrompt.swift App/JSONRenderEnvelope.swift App/NativeAIInterface+JSONRender.swift App/NativeAIComponentStream.swift App/ToolInputValidator.swift App/MissingRecordNotice.swift App/MemoraModel+AnswerCitations.swift App/ProjectCitationTargets.swift -D INTELLIGENT_UI_CHECKS -D PERSON_PROVENANCE_CHECKS -enable-bare-slash-regex Shared/MemoraIcon.swift App/LocalStore.swift App/Person.swift App/PersonIdentity.swift \
  App/PersonAIContext.swift App/MemoraModel+PersonPrivacy.swift App/PersonSelectionOption.swift App/PersonTaskAssociation.swift App/PersonMemory.swift App/PersonConversationSummary.swift \
  App/MemoraTask.swift App/TaskRelationships.swift App/TaskProgress.swift App/TaskOwnership.swift App/TaskHierarchy.swift \
  App/RecordPrivacy.swift App/RecordAccessPolicy.swift App/SummarySensitivity.swift App/RecordPrivacyTarget.swift \
  App/IdentifiableIndex.swift App/UndoAction.swift App/SummaryActionItem.swift App/AIPluginExecutionPolicy.swift \
  App/AgentToolCall.swift App/AgentToolOutcome.swift App/AgentStep.swift App/AIJournalPrivacy.swift App/LifeLogKind.swift App/LifeLogOrigin.swift \
  App/MemoraModel+People.swift App/MemoraModel+Tasks.swift App/MemoraModel+PersonScope.swift App/MemoraModel+PersonTools.swift \
  App/LifeLogEntry.swift App/LifeLogSource.swift App/TrashedLifeLogEntry.swift App/AIChatSource.swift App/AIChatScope.swift App/ReviewPeriod.swift App/AIRecordFingerprint.swift \
  App/MemoraModel+Journal.swift App/MemoraModel+JournalPeople.swift App/MemoraModel+RecordPrivacy.swift App/MemoraModel+AutomaticRecordTools.swift \
  tools/checks/PersonFixtureModel.swift App/ProjectCitation.swift App/AIAttachment.swift App/AIAttachmentFileReference.swift App/AIConversationEntry.swift App/JSONRenderSnapshot.swift App/AIEpisode.swift App/AIRecordReference.swift App/ArtifactProvenance.swift App/ArtifactProjectSourceReference.swift App/AIConversationProvenance.swift App/AgentSourceReference.swift App/MemoraModel+Glossary.swift App/AICalendarEventReference.swift App/AICalendarReadSnapshot.swift App/MemoraModel+CalendarContext.swift App/MemoraModel+AIProvenance.swift App/ProjectSource.swift App/MemoraDocumentKind.swift App/SlideArchetype.swift App/SlideContent.swift App/PresentationTheme.swift App/PresentationElement.swift App/PresentationText.swift App/TokenEstimate.swift App/PresentationEvidencePack.swift App/PresentationTypography.swift App/PresentationLayoutEngine.swift App/SlidePage.swift App/SlidePageLayout.swift App/PresentationValidator.swift App/PresentationExportCheck.swift App/PresentationOOXML.swift App/PresentationToolInput.swift App/DocumentSlide.swift App/PresentationPlan.swift App/DocumentArtifactRevision.swift App/MemoraDocument.swift App/MailDraft.swift App/ArtifactSourceTarget.swift App/ArtifactSourceRow.swift App/MemoraModel+ArtifactProvenance.swift App/MemoraModel+Documents.swift App/MemoraModel+MailDrafts.swift App/MemoraModel+MailDraftTool.swift App/AIInterfaceReferenceTarget.swift App/MemoraModel+IntelligentUI.swift App/MemoraModel+AnswerExport.swift App/AIAnswerShareContent.swift tools/checks/IntelligentUIContextChecks.swift "${extra_sources[@]}" "$entrypoint" -o "$check_dir/people"
"$check_dir/people"
