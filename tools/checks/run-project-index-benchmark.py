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
names = ['ProjectCitation', 'ProjectEvidenceChunk', 'ProjectEvidenceInput', 'ProjectSourceText', 'ProjectContextBuilder', 'ProjectSearchIndex']
with tempfile.TemporaryDirectory(prefix='memora-index-', dir=os.environ.get('MEMORA_CHECK_TMPDIR')) as folder:
    paths = []
    for name in names:
        path = Path('App')/(name + '.swift')
        if args.before:
            path = Path(folder)/(name + '.swift')
            path.write_text(subprocess.check_output(['git', 'show', f'18a65ec73fc94957c65e6289258f21ada4990c09:App/{name}.swift'], text=True))
        paths.append(str(path))
    binary = str(Path(folder)/'index')
    subprocess.run(['swiftc', '-O', *paths, 'tools/checks/ProjectIndexBenchmark.swift', '-o', binary], check=True)
    subprocess.run([binary], check=True)
