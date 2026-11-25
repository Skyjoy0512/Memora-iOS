#!/usr/bin/env python3
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

os.chdir(Path(__file__).resolve().parents[2])
parser = argparse.ArgumentParser()
parser.add_argument('--before', action='store_true')
args = parser.parse_args()
with tempfile.TemporaryDirectory(prefix='memora-store-', dir=os.environ.get('MEMORA_CHECK_TMPDIR')) as folder:
    folder = Path(folder)
    source = Path('App/LocalStore.swift')
    if args.before:
        text = subprocess.check_output(['git', 'show', '18a65ec73fc94957c65e6289258f21ada4990c09:App/LocalStore.swift'], text=True)
        # Constructor injection only; all baseline SQL, locks, reads, writes and
        # transactions remain unchanged. This avoids touching the real store.
        text = text.replace('  private init() {', '  init(fileURL overrideURL: URL? = nil) {')
        text = text.replace('    fileURL = base', '    fileURL = overrideURL ?? base')
        source = folder/'LocalStore.swift'
        source.write_text(text)
    binary = folder/'store'
    subprocess.run(['swiftc', '-O', str(source), 'tools/checks/LocalStoreChecks.swift', '-o', str(binary)], check=True)
    subprocess.run([str(binary), str(folder), *(['--historical-baseline'] if args.before else [])], check=True,
                   timeout=60, env={**os.environ, 'SWIFT_BACKTRACE': 'enable=no'})
