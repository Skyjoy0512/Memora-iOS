#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-backup.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc App/Meeting.swift App/MeetingSource.swift App/MeetingStatus.swift App/RecordingMarker.swift App/TranscriptSegment.swift App/SpeakerIdentificationStatus.swift \
  App/SourceSummaryOptions.swift App/SummaryLength.swift App/SummaryEngineChoice.swift App/AIAttachmentCitation.swift Shared/MemoraIcon.swift App/LocalStore.swift App/AIMemory.swift App/AIMemory+Editing.swift \
  App/ProjectCitation.swift App/AIAttachment.swift App/AIAttachmentFileReference.swift App/AIConversationEntry.swift App/AIEpisode.swift App/AIConversationProvenance.swift App/AIRecordReference.swift App/ArtifactProvenance.swift App/ArtifactProjectSourceReference.swift App/RecordPrivacyTarget.swift \
  App/MailDraft.swift App/PresentationPlan.swift App/DocumentArtifactRevision.swift App/MemoraDocument.swift App/MemoraDocumentKind.swift App/SlideArchetype.swift App/SlideContent.swift App/PresentationTheme.swift App/PresentationElement.swift App/PresentationText.swift App/TokenEstimate.swift App/PresentationEvidencePack.swift App/PresentationTypography.swift App/PresentationLayoutEngine.swift App/SlidePage.swift App/SlidePageLayout.swift App/PresentationValidator.swift App/PresentationExportCheck.swift App/PresentationOOXML.swift App/PresentationToolInput.swift App/DocumentSlide.swift \
  App/CompanyTemplate.swift App/CompanyTemplateEngine.swift App/CompanyPresentationProfile.swift App/CompanyPresentationAnalyzer.swift App/OfficeTemplateTextPart.swift App/DOCXWriter.swift App/ZipArchive.swift App/ProjectSourceText.swift \
  App/OfficeArchiveReader.swift App/OfficeXMLDocument.swift App/OfficeDocumentExtraction.swift \
  App/ProjectSource.swift App/ProjectSourceURL.swift App/RecordPrivacy.swift App/SummarySensitivity.swift \
  App/WebResearchReport.swift App/WebResearchSource.swift App/ResearchPlan.swift \
  App/MemoraSkill.swift App/MemoraSkill+Business.swift App/MemoraSkill+Workflows.swift App/MemoraSkillMarkdown.swift App/SkillSelection.swift \
  App/BackupPackage.swift App/BackupPackageFile.swift App/ProjectWorkspaceBackup.swift App/BackupRestoreTransaction.swift \
  tools/checks/BackupRestoreChecks.swift -o "$check_dir/backup"
"$check_dir/backup"
