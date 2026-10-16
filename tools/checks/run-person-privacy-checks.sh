#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-person-privacy.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc -D PERSON_PROVENANCE_CHECKS -enable-bare-slash-regex Shared/MemoraIcon.swift App/LocalStore.swift App/Person.swift App/PersonIdentity.swift \
  App/PersonAIContext.swift App/MemoraModel+PersonPrivacy.swift App/PersonSelectionOption.swift App/PersonTaskAssociation.swift App/PersonMemory.swift App/PersonConversationSummary.swift \
  App/MemoraTask.swift App/TaskRelationships.swift App/TaskProgress.swift App/TaskOwnership.swift App/TaskHierarchy.swift \
  App/RecordPrivacy.swift App/RecordAccessPolicy.swift App/SummarySensitivity.swift App/RecordPrivacyTarget.swift \
  App/IdentifiableIndex.swift App/UndoAction.swift App/SummaryActionItem.swift App/AIPluginExecutionPolicy.swift \
  App/AgentToolCall.swift App/AgentToolOutcome.swift App/AgentStep.swift App/AIJournalPrivacy.swift App/LifeLogKind.swift App/LifeLogOrigin.swift \
  App/MemoraModel+People.swift App/MemoraModel+Tasks.swift App/MemoraModel+PersonScope.swift App/MemoraModel+PersonTools.swift \
  App/LifeLogEntry.swift App/LifeLogSource.swift App/TrashedLifeLogEntry.swift App/AIChatSource.swift App/AIChatScope.swift App/ReviewPeriod.swift App/AIRecordFingerprint.swift \
  App/MemoraModel+Journal.swift App/MemoraModel+JournalPeople.swift App/MemoraModel+RecordPrivacy.swift App/MemoraModel+AutomaticRecordTools.swift \
  tools/checks/PersonFixtureModel.swift App/AIConversationEntry.swift App/AIEpisode.swift App/AIRecordReference.swift App/AIConversationProvenance.swift App/AgentSourceReference.swift App/MemoraModel+Glossary.swift App/MemoraModel+AIProvenance.swift tools/checks/PersonPrivacyChecks.swift -o "$check_dir/people"
"$check_dir/people"
