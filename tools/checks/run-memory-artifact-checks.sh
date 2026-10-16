#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-memory-artifact.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc Shared/MemoraIcon.swift App/AIPluginIcon.swift App/MemoraSkill.swift App/MemoraSkill+Business.swift App/MemoraSkillMarkdown.swift tools/checks/PluginIconChecks.swift -o "$check_dir/icons"
"$check_dir/icons"
swiftc App/PersonConversationSummary.swift tools/checks/PersonSummaryChecks.swift -o "$check_dir/person"
"$check_dir/person"
swiftc App/WebResearchSource.swift App/WebResearchReport.swift App/ResearchPlan.swift App/ResearchLoop.swift App/RecordPrivacyTarget.swift App/AIRecordReference.swift App/ArtifactProvenance.swift App/ArtifactProjectSourceReference.swift App/MailDraft.swift tools/checks/ResearchLoopChecks.swift -o "$check_dir/research"
"$check_dir/research"
swiftc -enable-bare-slash-regex Shared/MemoraIcon.swift App/RecordPrivacyTarget.swift App/AnswerSourceCitation.swift App/ArtifactSourceTarget.swift App/ArtifactProvenance.swift App/ArtifactProjectSourceReference.swift App/AIRecordReference.swift App/RecordPrivacy.swift App/SummarySensitivity.swift App/RecordAccessPolicy.swift App/AIPluginExecutionPolicy.swift App/AIRecordFingerprint.swift App/AgentSourceReference.swift App/AgentToolOutcome.swift App/ProjectSourceText.swift App/MemoraModel+AgentSources.swift tools/checks/AgentSourceChecks.swift -o "$check_dir/sources"
"$check_dir/sources"
bash tools/checks/run-artifact-checks.sh
bash tools/checks/run-backup-restore-checks.sh
bash tools/checks/run-person-task-checks.sh
bash tools/checks/run-person-journal-checks.sh
bash tools/checks/run-person-privacy-checks.sh
bash tools/checks/run-artifact-provenance-checks.sh
bash tools/checks/run-inline-citation-checks.sh
