#!/usr/bin/env python3
"""Production composer recovery and SQLite transactions; all paths are isolated."""
from pathlib import Path
import os
import subprocess
import tempfile

os.chdir(Path(__file__).resolve().parents[2])
model = Path('App/MemoraModel.swift').read_text()
assert 'var didFailToReadStore = composerStoreReadFailed' in model
assert 'composerStoreReadFailed = failure == .unavailable' in model
assert 'composerDraftFailure == nil' in model[model.index('  var composerDraft ='):model.index('  var composerMentionCursorRequest:')]
assert model[model.index('  private func scheduleComposerDraftSave()'):].count('composerDraftFailure == nil') >= 2
for name in ['Conversation', 'Plugins']:
    assert 'composerDraftFailure == nil' in Path(f'App/MemoraModel+{name}.swift').read_text()
with tempfile.TemporaryDirectory(prefix='memora-composer-recovery-', dir=os.environ.get('MEMORA_CHECK_ROOT')) as temporary:
    root = Path(temporary)
    store = root / 'IsolatedLocalStore.swift'
    # Only the default singleton destination changes. SQL, locks and transactions are production.
    store.write_text(Path('App/LocalStore.swift').read_text().replace(
        'static let shared = LocalStore()',
        'static let shared = LocalStore(fileURL: URL(fileURLWithPath: CommandLine.arguments[1]))'))
    reference = root / 'IsolatedAttachmentReference.swift'
    # resolve() is still real, but it must never read the host account's Documents.
    reference.write_text(Path('App/AIAttachmentFileReference.swift').read_text().replace(
        'FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]',
        'URL(fileURLWithPath: CommandLine.arguments[1]).deletingLastPathComponent()'))
    binary = root / 'checks'
    subprocess.run(['swiftc', '-DDEBUG', str(store), str(reference), 'App/RecordStore.swift',
                    'App/DraftStore.swift', 'App/LocalSaveFailure.swift', 'App/ComposerMention.swift',
                    'App/AIAttachment.swift', 'App/ComposerDraftSnapshot.swift', 'App/ComposerDraftStore.swift',
                    'App/ComposerDraftRecoveryArchive.swift', 'App/MemoraModel+ComposerRecovery.swift',
                    'tools/checks/ComposerRecoveryChecks.swift', '-o', str(binary)], check=True)
    subprocess.run([str(binary), str(root / 'store.sqlite')], check=True,
                   env=dict(os.environ, SWIFT_BACKTRACE='enable=no'))
