#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-artifact-operations.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
export MEMORA_WORKSPACE_FILES_DIRECTORY="$check_dir/workspace"
entrypoint=tools/checks/ArtifactOperationsChecks.swift
extra_sources=()
if [[ "${1:-}" == --presentation-revision ]]; then
  entrypoint=tools/checks/PresentationRevisionAccessChecks.swift
  extra_sources=(App/MemoraModel+PresentationRevision.swift)
elif [[ "${1:-}" == --company-reexport ]]; then
  entrypoint=tools/checks/CompanyPresentationReexportChecks.swift
elif [[ "${1:-}" == --company-preview ]]; then
  entrypoint=tools/checks/CompanyPresentationPreviewAccessChecks.swift
  extra_sources=(App/CompanyPresentationPreview.swift App/CompanyPresentationColor.swift App/CompanyPresentationDecorationReader.swift App/CompanyPresentationPreviewRequest.swift App/MemoraModel+CompanyPresentationPreview.swift tools/checks/CompanyPresentationPreviewGate.swift)
fi
swiftc App/SummaryKnowledge.swift App/SourceSummaryOptions.swift App/SummaryLength.swift App/SummaryEngineChoice.swift App/AIAttachmentCitation.swift -enable-bare-slash-regex -D MEMORA_HOST_CHECKS -D PERSON_PROVENANCE_CHECKS -D ARTIFACT_PROVENANCE_CHECKS -D ASK_AI_SCENARIO_CHECKS \
  Shared/MemoraIcon.swift App/LocalStore.swift App/Person.swift App/PersonIdentity.swift App/PersonAIContext.swift \
  App/MemoraModel+PersonPrivacy.swift App/PersonSelectionOption.swift App/PersonTaskAssociation.swift App/PersonMemory.swift App/PersonConversationSummary.swift \
  App/MemoraTask.swift App/TaskRelationships.swift App/TaskProgress.swift App/TaskOwnership.swift App/TaskHierarchy.swift \
  App/RecordPrivacy.swift App/RecordAccessPolicy.swift App/SummarySensitivity.swift App/RecordPrivacyTarget.swift \
  App/IdentifiableIndex.swift App/UndoAction.swift App/SummaryActionItem.swift App/AIPluginExecutionPolicy.swift \
  App/AgentToolCall.swift App/AgentToolOutcome.swift App/AgentStep.swift App/AIJournalPrivacy.swift App/LifeLogKind.swift App/LifeLogOrigin.swift \
  App/MemoraModel+People.swift App/MemoraModel+Tasks.swift App/MemoraModel+PersonScope.swift App/MemoraModel+PersonTools.swift \
  App/LifeLogEntry.swift App/LifeLogSource.swift App/TrashedLifeLogEntry.swift App/AIChatSource.swift App/AIChatScope.swift App/ReviewPeriod.swift App/AIRecordFingerprint.swift \
  App/MemoraModel+Journal.swift App/MemoraModel+JournalPeople.swift App/MemoraModel+RecordPrivacy.swift App/MemoraModel+AutomaticRecordTools.swift \
  tools/checks/PersonFixtureModel.swift App/ProjectCitation.swift App/AIAttachment.swift App/AIAttachmentFileReference.swift App/AIConversationEntry.swift App/JSONRenderSnapshot.swift App/AIEpisode.swift App/AIRecordReference.swift App/ArtifactProvenance.swift \
  App/ArtifactProjectSourceReference.swift App/AIConversationProvenance.swift App/AgentSourceReference.swift App/MemoraModel+Glossary.swift \
  App/AICalendarEventReference.swift App/AICalendarReadSnapshot.swift App/MemoraModel+CalendarContext.swift App/MemoraModel+AIProvenance.swift App/ProjectSource.swift App/MemoraDocumentKind.swift App/SlideArchetype.swift App/SlideContent.swift App/PresentationTheme.swift App/PresentationElement.swift App/PresentationText.swift App/TokenEstimate.swift App/PresentationEvidencePack.swift App/PresentationTypography.swift App/PresentationLayoutEngine.swift App/PresentationValidator.swift App/PresentationExportCheck.swift App/PresentationOOXML.swift App/PresentationToolInput.swift App/DocumentSlide.swift App/PresentationPlan.swift App/DocumentArtifactRevision.swift App/MemoraDocument.swift App/MailDraft.swift \
  App/ArtifactSourceTarget.swift App/ArtifactSourceTarget+Presentation.swift App/ArtifactSourceRow.swift App/MemoraModel+ArtifactProvenance.swift App/MemoraModel+Documents.swift \
  App/MemoraModel+MailDrafts.swift App/MemoraModel+DocumentArtifacts.swift App/ArtifactExportFile.swift \
  App/CompanyPresentationExportRequest.swift App/CompanyPresentationExportError.swift App/CompanyPresentationExportTransaction.swift App/MemoraModel+CompanyPresentationExports.swift \
  App/AnswerSourceCitation.swift App/AnswerCitations.swift App/MeetingLink.swift App/AIAnswerDocumentBuilder.swift App/NativeAIInterface.swift App/JSONRenderPrompt.swift App/JSONRenderEnvelope.swift App/NativeAIInterface+JSONRender.swift App/NativeAIComponentStream.swift App/ToolInputValidator.swift App/MissingRecordNotice.swift App/MemoraModel+AnswerCitations.swift App/ProjectCitationTargets.swift \
  App/ZipArchive.swift App/ProjectSourceText.swift App/OfficeArchiveReader.swift App/OfficeXMLDocument.swift App/OfficeDocumentExtraction.swift App/DOCXWriter.swift App/SlidePage.swift App/SlidePageLayout.swift App/PPTXWriter.swift App/CompanyPresentationExporter.swift App/OfficeXMLInsertion.swift \
  App/CompanyTemplate.swift App/CompanyTemplateEngine.swift App/CompanyPresentationProfile.swift App/CompanyPresentationAnalyzer.swift App/OfficeTemplateTextPart.swift App/ProjectSourceFiles.swift \
  ${extra_sources[@]+"${extra_sources[@]}"} "$entrypoint" -lsqlite3 -framework CryptoKit -o "$check_dir/operations"
"$check_dir/operations"
