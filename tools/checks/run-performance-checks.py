#!/usr/bin/env python3
"""Compare unchanged algorithm fixtures with a named, recoverable baseline."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
os.chdir(root)
parser = argparse.ArgumentParser()
parser.add_argument('--baseline', default='18a65ec73fc94957c65e6289258f21ada4990c09')
parser.add_argument('--before', action='store_true')
args = parser.parse_args()

def original(name):
    return subprocess.check_output(['git', 'show', f'{args.baseline}:App/{name}'], text=True)

def sections(source, name):
    begin = source.index('  private var fileSections:')
    end = source.index('  private func matchesQuery', begin)
    value = source[begin:end].replace('  private var fileSections: [FileDateSection] {', '  func build(_ matchingMeetings: [Meeting]) -> [FileDateSection] {')
    return f'struct {name} {{\n{value}\n}}\n'

with tempfile.TemporaryDirectory(prefix='memora-perf-', dir=os.environ.get('MEMORA_CHECK_TMPDIR')) as folder:
    folder = Path(folder)
    source = original('MemoraModel+AI.swift')
    begin = source.index('  static func rank(')
    end = source.index('  /// The text a record is searched by', begin)
    legacy = folder/'Legacy.swift'
    legacy.write_text('import Foundation\nenum LegacyRanking {\n' + source[begin:end] + '}\n' + sections(original('LibraryView.swift'), 'LegacySections'))
    current = folder/'Current.swift'
    current.write_text('import Foundation\n' + sections(original('LibraryView.swift') if args.before else Path('App/LibraryView.swift').read_text(), 'CurrentSections'))
    ranking = Path('App/MeetingRanking.swift')
    if args.before:
        ranking = folder/'Ranking.swift'
        ranking.write_text('import Foundation\nenum MeetingRanking {\n' + source[begin:end] + '}\n')
    binary = folder/'collections'
    subprocess.run(['swiftc', '-O', str(ranking), str(legacy), str(current), 'App/MemoraFormat.swift', 'tools/checks/CollectionPerformanceChecks.swift', '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
    paths = []
    for name in ['PerformanceLog.swift', 'RecordStore.swift']:
        path = Path('App')/name
        if args.before:
            path = folder/name
            text = original(name)
            if name == 'PerformanceLog.swift':
                text += '\nextension PerformanceLog { func flush() {}\nfunc flushNow() {} }\n'
            path.write_text(text)
        paths.append(str(path))
    binary = folder/'log'
    subprocess.run(['swiftc', '-O', '-DDEBUG', *(['-DBASELINE'] if args.before else []), *paths, 'tools/checks/PerformanceLogChecks.swift', '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
