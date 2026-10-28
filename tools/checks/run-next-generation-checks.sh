#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_root=${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}
check_dir=$(mktemp -d "$check_root/memora-nextgen-checks.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
bash tools/checks/run-summary-reading-checks.sh
swiftc App/JournalInsertionTime.swift tools/checks/JournalInsertionTimeChecks.swift -o "$check_dir/journal-insertion"
"$check_dir/journal-insertion"
swiftc App/CalendarEventEditPolicy.swift tools/checks/CalendarEventEditPolicyChecks.swift -o "$check_dir/calendar-edit-policy"
"$check_dir/calendar-edit-policy"
swiftc App/PersistenceFailurePresentation.swift tools/checks/PersistenceFailurePresentationChecks.swift -o "$check_dir/persistence-presentation"
"$check_dir/persistence-presentation"
swiftc -D MEMORA_HOST_CHECKS App/AIMemory.swift App/AIMemory+Editing.swift App/MemoryRetrievalItem.swift App/MemoryRetrievalOrchestrator.swift tools/checks/MemoryRetrievalChecks.swift -lsqlite3 -o "$check_dir/memory"
"$check_dir/memory"
bash tools/checks/run-memory-editing-checks.sh
bash tools/checks/run-project-source-storage-checks.sh
bash tools/checks/run-project-source-preparation-checks.sh
bash tools/checks/run-project-source-web-recovery-checks.sh
bash tools/checks/run-project-source-import-checks.sh
bash tools/checks/run-audio-import-checks.sh
bash tools/checks/run-notion-service-checks.sh
bash tools/checks/run-notion-agent-checks.sh
bash tools/checks/run-gmail-service-checks.sh
bash tools/checks/run-gmail-agent-checks.sh
bash tools/checks/run-mcp-agent-checks.sh
bash tools/checks/run-mcp-pinned-http-checks.sh
bash tools/checks/run-answer-presentation-checks.sh
swiftc App/Person.swift App/RecordPrivacy.swift App/SummarySensitivity.swift App/PersonIdentity.swift tools/checks/PersonIdentityChecks.swift -o "$check_dir/person-identity"
"$check_dir/person-identity"
swiftc App/ProjectTaskList.swift App/MemoraTask.swift App/TaskRelationships.swift App/TaskProgress.swift App/RecordPrivacy.swift App/SummarySensitivity.swift tools/checks/ProjectTaskListChecks.swift -o "$check_dir/project-tasks"
"$check_dir/project-tasks"
swiftc App/ProjectCitation.swift App/ProjectEvidenceChunk.swift App/ProjectContextBuilder.swift tools/checks/ProjectContextChecks.swift -o "$check_dir/project-context"
"$check_dir/project-context"
swiftc App/ProjectCitation.swift App/ProjectEvidenceChunk.swift App/ProjectEvidenceInput.swift App/ProjectSourceText.swift App/ProjectContextBuilder.swift App/ProjectSearchIndex.swift tools/checks/ProjectSearchIndexChecks.swift -lsqlite3 -o "$check_dir/project-index"
"$check_dir/project-index"
swiftc App/ProjectCitation.swift App/ProjectEvidenceChunk.swift App/ProjectEvidenceInput.swift App/ProjectSourceText.swift App/ProjectContextBuilder.swift App/ProjectSearchIndex.swift tools/checks/ProjectSearchQualityChecks.swift -lsqlite3 -o "$check_dir/project-quality"
"$check_dir/project-quality" tools/checks/fixtures/project-search-quality.json "$check_dir"
swiftc Shared/MemoraIcon.swift App/RecordPrivacy.swift App/SummarySensitivity.swift App/ProjectSource.swift App/ProjectSource+Presentation.swift tools/checks/ProjectSourceAvailabilityChecks.swift -o "$check_dir/source-availability"
"$check_dir/source-availability"
swiftc App/MCPDNSLookup.swift App/MCPClientError.swift App/MCPPublicAddressPolicy.swift App/RecordPrivacy.swift App/SummarySensitivity.swift App/ProjectSource.swift App/ProjectSourceText.swift App/ProjectSourceURL.swift App/WebSourceFailure.swift App/WebSourceRequest.swift App/WebSourceHTTPDecoder.swift App/PinnedHTTPSConnection.swift App/WebSourceTextExtraction.swift App/WebSourceFetcher.swift tools/checks/WebSourceChecks.swift -o "$check_dir/web-source"
python3 tools/checks/make-web-certificate-fixture.py "$check_dir/web.cer"
"$check_dir/web-source" "$check_dir/web.cer"
python3 tools/checks/make-office-fixtures.py "$check_dir/office-fixtures"
swiftc App/ZipArchive.swift App/ProjectSourceText.swift App/OfficeArchiveReader.swift App/OfficeXMLDocument.swift App/OfficeDocumentExtraction.swift tools/checks/OfficeDocumentChecks.swift -o "$check_dir/office"
"$check_dir/office" "$check_dir/office-fixtures"
swiftc Shared/MemoraIcon.swift App/AgentStep.swift App/AIAttachment.swift App/AIAttachmentFileReference.swift App/ComposerMention.swift App/AIAnswerDetails.swift App/AIChatSource.swift App/RecordPrivacyTarget.swift App/AIRecordReference.swift App/ArtifactProvenance.swift App/ArtifactProjectSourceReference.swift App/AIConversationProvenance.swift App/AgentSourceReference.swift App/AICalendarEventReference.swift App/AICalendarReadSnapshot.swift App/AIChatMessage.swift App/ToolInputValidator.swift App/NativeAIInterface.swift App/NativeAIComponentStream.swift App/AIConversationSnapshot.swift tools/checks/AIConversationSnapshotChecks.swift -o "$check_dir/conversation"
"$check_dir/conversation"
swiftc App/AIAttachment.swift App/AIAttachmentFileReference.swift App/PreparedAIAttachment.swift App/AgentAttachmentContext.swift App/AIPluginExecutionPolicy.swift App/AIAnswerFailure.swift App/AIAnswerResult.swift App/AgentToolCall.swift App/AgentToolOutcome.swift App/AgentTurn.swift App/AgentRunEvent.swift App/AgentConversationLoop.swift tools/checks/AgentAttachmentChecks.swift -o "$check_dir/agent-attachment"
"$check_dir/agent-attachment"
swiftc App/ReviewPeriod.swift App/AgentTaskDraft.swift tools/checks/AgentTaskDraftChecks.swift -o "$check_dir/task-drafts"
"$check_dir/task-drafts"
swiftc App/ConversationScrollState.swift tools/checks/ConversationScrollChecks.swift -o "$check_dir/conversation-scroll"
"$check_dir/conversation-scroll"
swiftc App/RelevantTextWindow.swift tools/checks/RelevantTextWindowChecks.swift -o "$check_dir/passage"
"$check_dir/passage"
swiftc App/AIAnswerFailure.swift App/AIAnswerResult.swift App/AgentToolCall.swift App/AgentToolOutcome.swift App/AgentTurn.swift App/AgentRunEvent.swift App/AgentConversationLoop.swift tools/checks/AgentConversationLoopChecks.swift -o "$check_dir/agent-loop"
"$check_dir/agent-loop"
swiftc App/AgentToolOutcome.swift App/ProjectCitation.swift App/ProjectEvidenceChunk.swift App/ProjectContextBuilder.swift App/ScopedAgentEvidence.swift tools/checks/ScopedAgentEvidenceChecks.swift -o "$check_dir/scoped-evidence"
"$check_dir/scoped-evidence"
swiftc App/BoundedTextReader.swift App/AIAttachment.swift App/PreparedAIAttachment.swift App/AIQueryScope.swift tools/checks/AttachmentScopeChecks.swift -o "$check_dir/attachments"
"$check_dir/attachments"
swiftc App/ProjectSourceFiles.swift App/ProjectSourceText.swift App/ProjectSourceTextReader.swift tools/checks/ProjectSourceReadChecks.swift -o "$check_dir/source-read"
"$check_dir/source-read"
swiftc App/ProjectCitation.swift App/ProjectChatTurn.swift App/ProjectChatThread.swift App/ProjectChatHistory.swift tools/checks/ProjectChatHistoryChecks.swift -o "$check_dir/project-history"
"$check_dir/project-history"
swiftc App/AIAnswerFailure.swift App/AgentToolCall.swift App/AgentTurn.swift App/CloudAgentTurnDecoder.swift App/CloudSummaryResponse.swift App/CloudStreamAccumulator.swift tools/checks/CloudStreamChecks.swift -o "$check_dir/stream"
"$check_dir/stream"
swiftc App/AIAnswerFailure.swift App/AgentToolCall.swift App/AgentTurn.swift App/CloudAgentTurnDecoder.swift App/AIAnswerResult.swift App/AgentToolOutcome.swift App/AgentRunEvent.swift App/AgentConversationLoop.swift tools/checks/CloudAgentTurnChecks.swift -o "$check_dir/turn-decoder"
"$check_dir/turn-decoder"
swiftc -D DEBUG App/SummaryDiagnostics.swift App/AIAnswerFailure.swift App/AgentSessionBudget.swift App/AgentToolCall.swift App/AgentTurn.swift App/CloudAgentTurnDecoder.swift App/CloudSummaryResponse.swift App/CloudStreamAccumulator.swift App/CloudSSEEventDecoder.swift App/CloudTurnStreamReader.swift App/SyntheticAIEventStream.swift tools/checks/CloudSSETransportChecks.swift -o "$check_dir/sse-transport"
"$check_dir/sse-transport"
swiftc App/ToolInputValidator.swift App/NativeAIInterface.swift App/NativeAIComponentStream.swift tools/checks/NativeAIInterfaceChecks.swift -o "$check_dir/ui"
"$check_dir/ui"
swiftc App/SemanticToolDiscovery.swift App/MemoraSkill.swift App/MemoraSkill+Business.swift App/MemoraSkillMarkdown.swift tools/checks/DiscoverySkillChecks.swift -o "$check_dir/skills"
"$check_dir/skills"
swiftc Shared/MemoraIcon.swift App/ResidentAgent.swift App/ResidentTrigger.swift App/ResidentExecutionLimits.swift tools/checks/ResidentLimitsChecks.swift -o "$check_dir/residents"
"$check_dir/residents"
swiftc Shared/MemoraAppLink.swift Shared/MemoraWidgetSnapshot.swift Shared/MemoraWidgetSnapshotStore.swift tools/checks/SystemIntegrationChecks.swift -o "$check_dir/system"
"$check_dir/system" "$check_dir"
TMPDIR="$check_dir/" bash tools/checks/run-ask-ai-plugin-checks.sh
bash tools/checks/run-ask-ai-scenario-checks.sh
bash tools/checks/run-artifact-operation-checks.sh
bash tools/checks/run-artifact-operation-checks.sh --company-reexport
bash tools/checks/run-company-presentation-checks.sh --preview
bash tools/checks/run-artifact-operation-checks.sh --company-preview
bash tools/checks/run-memory-artifact-checks.sh
bash tools/checks/run-cloud-session-checks.sh
bash tools/checks/run-intelligent-ui-checks.sh
bash tools/checks/run-openui-native-polish-checks.sh
bash tools/checks/run-artifact-provenance-checks.sh --interface-task-execution
bash tools/checks/run-artifact-provenance-checks.sh --task-proposals
bash tools/checks/run-artifact-provenance-checks.sh --calendar-interface

bash tools/checks/run-branch-integration-checks.sh
