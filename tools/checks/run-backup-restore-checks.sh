#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-backup.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc Shared/MemoraIcon.swift App/LocalStore.swift App/AIMemory.swift App/AIMemory+Editing.swift \
  App/AIConversationEntry.swift App/AIEpisode.swift App/AIConversationProvenance.swift App/AIRecordReference.swift App/ArtifactProvenance.swift App/ArtifactProjectSourceReference.swift App/RecordPrivacyTarget.swift \
  App/MailDraft.swift App/MemoraDocument.swift App/MemoraDocumentKind.swift App/DocumentSlide.swift \
  App/CompanyTemplate.swift App/CompanyTemplateEngine.swift App/OfficeTemplateTextPart.swift App/DOCXWriter.swift App/ZipArchive.swift App/ProjectSourceText.swift \
  App/OfficeArchiveReader.swift App/OfficeXMLDocument.swift App/OfficeDocumentExtraction.swift \
  App/ProjectSource.swift App/ProjectSourceURL.swift App/RecordPrivacy.swift App/SummarySensitivity.swift \
  App/WebResearchReport.swift App/WebResearchSource.swift App/ResearchPlan.swift \
  App/MemoraSkill.swift App/MemoraSkill+Business.swift App/MemoraSkillMarkdown.swift App/SkillSelection.swift \
  App/BackupPackage.swift App/BackupPackageFile.swift App/ProjectWorkspaceBackup.swift App/BackupRestoreTransaction.swift \
  tools/checks/BackupRestoreChecks.swift -o "$check_dir/backup"
"$check_dir/backup"
