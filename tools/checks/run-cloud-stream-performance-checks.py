#!/usr/bin/env python3
"""Same optimized host benchmark and exact output assertions for either revision."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
os.chdir(root)
parser = argparse.ArgumentParser()
parser.add_argument('--baseline-ref')
parser.add_argument('--iterations', type=int, default=21)
args = parser.parse_args()
if not 1 <= args.iterations <= 101:
    parser.error('iterations must be 1...101')
with tempfile.TemporaryDirectory(prefix='memora-stream-performance-', dir=os.environ.get('MEMORA_CHECK_TMPDIR')) as folder:
    folder = Path(folder)
    accumulator = root / 'App/CloudStreamAccumulator.swift'
    if args.baseline_ref:
        data = subprocess.check_output(['git', 'show', args.baseline_ref + ':App/CloudStreamAccumulator.swift'])
        accumulator = folder / 'CloudStreamAccumulator.swift'
        accumulator.write_bytes(data)
    files = ['AIAnswerFailure', 'AgentToolCall', 'AgentTurn', 'CloudAgentTurnDecoder', 'CloudSummaryResponse']
    binary = folder / 'stream-performance'
    subprocess.run(['swiftc', '-O', *['App/' + name + '.swift' for name in files], str(accumulator),
                    'tools/checks/CloudStreamPerformanceChecks.swift', '-o', str(binary)], check=True)
    # Each case gets its own process; release Foundation JSON temporaries each
    # trial so RSS is not a cumulative artifact of six different workloads.
    for provider in ['chat', 'anthropic']:
        for count in [1000, 5000, 10000]:
            subprocess.run([str(binary), str(args.iterations), provider, str(count)], check=True, timeout=120)
