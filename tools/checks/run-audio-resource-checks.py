#!/usr/bin/env python3
"""Compare identical host workloads; never infer device power from these results."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', default='4dbc5fa')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    results = []
    with tempfile.TemporaryDirectory(prefix='memora-audio-', dir=os.environ.get('MEMORA_CHECK_TMPDIR')) as folder:
        scratch = Path(folder)
        for version in ['before', 'after']:
            converter = ROOT / 'App/LiveAudioBufferConverter.swift'
            if version == 'before':
                converter = scratch / 'LiveAudioBufferConverter.swift'
                converter.write_bytes(subprocess.check_output(['git', 'show', args.baseline + ':App/LiveAudioBufferConverter.swift'], cwd=ROOT))
            binary = scratch / version
            subprocess.run(['swiftc', '-O', *(['-DBASELINE'] if version == 'before' else []),
                str(converter), str(ROOT / 'App/LiveTranscriptHistory.swift'), str(ROOT / 'App/RecordingPowerMode.swift'),
                str(ROOT / 'tools/checks/AudioResourceChecks.swift'), '-o', str(binary)], check=True)
            for minutes in [15, 60, 120]:
                result = json.loads(subprocess.check_output([str(binary), str(minutes)], text=True))
                result['version'] = version
                results.append(result)
                print(json.dumps(result), flush=True)
    if args.output:
        args.output.write_text(json.dumps({'baseline': args.baseline, 'host': os.uname().machine,
            'scope': 'Synthetic display history and PCM conversion only; no SpeechAnalyzer, microphone, or battery measurement',
            'results': results}, indent=2) + '\n')

if __name__ == '__main__':
    main()
