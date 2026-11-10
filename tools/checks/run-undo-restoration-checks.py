#!/usr/bin/env python3
"""Production delete/restore/undo orchestration with isolated real SQLite."""
from pathlib import Path
import os
import subprocess
import tempfile

os.chdir(Path(__file__).resolve().parents[2])
tasks = Path('App/MemoraModel+Tasks.swift').read_text()
trash = Path('App/MemoraModel+Trash.swift').read_text()
journal = Path('App/MemoraModel+Journal.swift').read_text()
methods = tasks[tasks.index('  @discardableResult\n  func deleteTask('):tasks.index('  @discardableResult\n  func addTask(')]
methods += trash[trash.index('  func deleteMeeting('):trash.index('  /// Removes a trashed record and its media')]
methods += journal[journal.index('  /// Moves an entry to the trash'):journal.index('  func permanentlyDeleteTrashedLifeLogEntry(')]
undo = Path('App/MemoraModel+Undo.swift').read_text().replace('import UIKit\n', '')
with tempfile.TemporaryDirectory(prefix='memora-undo-', dir=os.environ.get('MEMORA_CHECK_ROOT')) as temporary:
    root = Path(temporary)
    production = root / 'ProductionUndo.swift'
    production.write_text('import Foundation\nextension MemoraModel {\n' + methods + '}\n' + undo)
    binary = root / 'checks'
    subprocess.run(['swiftc', 'App/LocalStore.swift', 'App/UndoAction.swift', 'App/TrashedRecord.swift',
                    'App/TrashedLifeLogEntry.swift', 'App/MemoraTask.swift', 'App/TaskRelationships.swift',
                    'App/TaskProgress.swift', 'App/RecordPrivacy.swift', 'App/SummarySensitivity.swift',
                    str(production), 'tools/checks/UndoRestorationChecks.swift', '-o', str(binary)], check=True)
    subprocess.run([str(binary), str(root)], check=True, env=dict(os.environ, SWIFT_BACKTRACE='enable=no'))
