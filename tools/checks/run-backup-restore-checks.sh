#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-backup.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
python3 - "$check_dir/TeamShareProduction.swift" <<'PY'
from pathlib import Path
import sys
source = Path('App/MemoraModel+Backup.swift').read_text()
method = source[source.index('  func makeTeamSharePackage('):source.index('  /// Shares a project')]
# Suspend only at the writer boundary to deterministically revoke access during export.
method = method.replace('try BackupPackage.write(', 'try await TeamSharePackageWriter.write(')
materialize = source[source.index('  private func materializePendingLegacyPhotos('):source.index('  /// True when a restore')]
Path(sys.argv[1]).write_text('import Foundation\nextension TeamShareModelFixture {\n' + materialize + method + '}\n')
PY
swiftc App/TemplateSummary.swift App/SummarySection.swift App/SummaryEvidence.swift App/SummaryEvidenceLink.swift App/GeneratedSummaryEvidence.swift App/SummaryPreferences.swift App/SummaryProcessingMode.swift App/SummaryKnowledge.swift App/SummaryModeClassifier.swift App/SummaryModeBreadcrumb.swift App/RecordingAudioPart.swift App/RecordingAudioManifest.swift App/Meeting.swift App/MeetingSource.swift App/MeetingStatus.swift App/RecordingMarker.swift App/TranscriptSegment.swift App/SpeakerIdentificationStatus.swift \
  App/SourceSummaryOptions.swift App/SummaryLength.swift App/SummaryEngineChoice.swift App/AIAttachmentCitation.swift Shared/MemoraIcon.swift App/LocalStore.swift App/AIMemory.swift App/AIMemory+Editing.swift \
  App/ProjectCitation.swift App/AIAttachment.swift App/AIAttachmentFileReference.swift App/AIConversationEntry.swift App/JSONRenderSnapshot.swift App/AIEpisode.swift App/AIConversationProvenance.swift App/AIRecordReference.swift App/ArtifactProvenance.swift App/ArtifactProjectSourceReference.swift App/RecordPrivacyTarget.swift \
  App/MailDraft.swift App/PresentationPlan.swift App/DocumentArtifactRevision.swift App/MemoraDocument.swift App/MemoraDocumentKind.swift App/SlideArchetype.swift App/SlideContent.swift App/PresentationTheme.swift App/PresentationElement.swift App/PresentationText.swift App/TokenEstimate.swift App/PresentationEvidencePack.swift App/PresentationTypography.swift App/PresentationLayoutEngine.swift App/SlidePage.swift App/SlidePageLayout.swift App/PresentationValidator.swift App/PresentationExportCheck.swift App/PresentationOOXML.swift App/PresentationToolInput.swift App/DocumentSlide.swift \
  App/CompanyTemplate.swift App/CompanyTemplateEngine.swift App/CompanyPresentationProfile.swift App/CompanyPresentationAnalyzer.swift App/OfficeTemplateTextPart.swift App/DOCXWriter.swift App/ZipArchive.swift App/ProjectSourceText.swift \
  App/OfficeArchiveReader.swift App/OfficeXMLDocument.swift App/OfficeDocumentExtraction.swift \
  App/ProjectSource.swift App/ProjectSourceURL.swift App/RecordPrivacy.swift App/SummarySensitivity.swift \
  App/WebResearchReport.swift App/WebResearchSource.swift App/ResearchPlan.swift \
  App/MemoraSkill.swift App/MemoraSkill+Business.swift App/MemoraSkill+Workflows.swift App/MemoraSkill+Breadth.swift App/MemoraSkillMarkdown.swift App/SkillSelection.swift \
  App/BackupPackage.swift App/BackupPackageFile.swift App/ProjectWorkspaceBackup.swift App/BackupRestoreTransaction.swift \
  App/Person.swift App/RecordAccessPolicy.swift App/TeamShareError.swift \
  tools/checks/BackupRestoreChecks.swift tools/checks/TeamSharePackageChecks.swift "$check_dir/TeamShareProduction.swift" -o "$check_dir/backup"
"$check_dir/backup"
