#!/usr/bin/env python3
"""Exercise actual Meeting/media-removal methods, file containment and SQLite transactions."""
from pathlib import Path
import os
import subprocess
import tempfile

os.chdir(Path(__file__).resolve().parents[2])
media = Path('App/MediaFiles.swift').read_text()
paths = media[media.index('  static func isPlainName('):media.index('  /// The folder photos')]
delete = media[media.index('  @discardableResult\n  static func delete(_ url:'):media.rindex('\n}')]
# Keep containment and deletion decisions intact; inject only the filesystem failure boundary.
delete = delete.replace('try FileManager.default.removeItem(at: target)', 'try removeFixtureFile(at: target)')
trash = Path('App/MemoraModel+Trash.swift').read_text()
methods = trash[trash.index('  func permanentlyDeleteTrashedRecord('):trash.rindex('\n}')]
journal = Path('App/MemoraModel+Journal.swift').read_text()
methods += '\n' + journal[journal.index('  func permanentlyDeleteTrashedLifeLogEntry('):journal.index('  /// Brings in journal records')]
usage = Path('App/StorageUsageView.swift').read_text()
usage = usage[usage.index('private struct AudioUsage'):].replace('private struct AudioUsage', 'struct AudioUsage', 1)
with tempfile.TemporaryDirectory(prefix='memora-recording-media-', dir=os.environ.get('MEMORA_CHECK_ROOT')) as temporary:
    root = Path(temporary)
    generated = root / 'ProductionFilePaths.swift'
    generated.write_text('import Foundation\nextension MediaFiles {\n' + paths + delete + '}\nextension MemoraModel {\n' + methods + '}\n' + usage)
    binary = root / 'checks'
    subprocess.run(['swiftc', 'Shared/MemoraIcon.swift', 'App/LocalStore.swift', 'App/Meeting.swift', 'App/Meeting+AudioFiles.swift',
                    'App/MeetingSource.swift', 'App/MeetingStatus.swift', 'App/TranscriptSegment.swift', 'App/SpeakerIdentificationStatus.swift',
                    'App/RecordPrivacy.swift', 'App/SummarySensitivity.swift', 'App/RecordingMarker.swift', 'App/UndoAction.swift', 'App/StorageUsage.swift',
                    'App/MemoraModel+Media.swift', 'tools/checks/RecordingRecoveryStoreFixture.swift',
                    'tools/checks/RecordingMediaChecks.swift', str(generated), '-lsqlite3', '-o', str(binary)], check=True)
    subprocess.run([str(binary), str(root)], check=True, env=dict(os.environ, SWIFT_BACKTRACE='enable=no'))
