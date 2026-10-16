#!/usr/bin/env python3
"""Same-process, alternating comparison of real incremental Markdown sources."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
os.chdir(root)
parser = argparse.ArgumentParser()
parser.add_argument('--baseline', default='1cb1d8d')
parser.add_argument('--output', type=Path)
args = parser.parse_args()
baseline = subprocess.check_output(['git', 'rev-parse', '--verify', args.baseline + '^{commit}'], text=True).strip()
with tempfile.TemporaryDirectory(prefix='memora-markdown-update-', dir=os.environ.get('MEMORA_CHECK_TMPDIR')) as folder:
    folder = Path(folder)
    files = []
    for name in ['MarkdownBlockParser.swift', 'IncrementalMarkdown.swift']:
        source = subprocess.check_output(['git', 'show', f'{baseline}:App/{name}'], text=True)
        source = source.replace('MarkdownBlockParser', 'BaselineMarkdownBlockParser').replace('IncrementalMarkdown', 'BaselineIncrementalMarkdown')
        path = folder/('Baseline' + name)
        path.write_text(source)
        files.append(str(path))
    current_parser = root/'App/MarkdownBlockParser.swift'
    binary = folder/'benchmark'
    subprocess.run(['swiftc', '-O', 'App/MarkdownBlock.swift', 'App/SourcedMarkdownBlock.swift',
                    'App/MarkdownFence.swift', str(current_parser), 'App/IncrementalMarkdown.swift',
                    *files, 'tools/checks/MarkdownUpdateBenchmark.swift', '-o', str(binary)], check=True)
    reports = json.loads(subprocess.check_output([str(binary)], text=True, timeout=120))
result = {'baseline_commit': baseline,
          'current_source_sha256': {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in
                                   ['App/MarkdownBlockParser.swift', 'App/IncrementalMarkdown.swift', 'tools/checks/MarkdownUpdateBenchmark.swift']},
          'architecture': platform.machine(), 'os': platform.mac_ver()[0],
          'compiler': subprocess.check_output(['swiftc', '--version'], text=True).strip(),
          'optimization': '-O', 'warmups': 2, 'samples': 21, 'order': 'alternating',
          'scope': 'Synthetic host parser CPU only; excludes network, SwiftUI layout, frames, main actor and iPhone Release',
          'results': reports}
encoded = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
print(encoded, end='')
if args.output:
    args.output.write_text(encoded)
