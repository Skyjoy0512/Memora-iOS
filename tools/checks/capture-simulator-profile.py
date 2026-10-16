#!/usr/bin/env python3
"""Capture one already-running, explicitly selected simulator app; never build/reset it."""
import argparse
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import uuid
import xml.etree.ElementTree as ET

from simulator_profile_summary import summarize


def command(arguments, timeout=60):
    return subprocess.check_output(arguments, text=True, stderr=subprocess.STDOUT, timeout=timeout)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--simulator', type=uuid.UUID, required=True)
    parser.add_argument('--app', type=Path, required=True, help='Exact installed Bitrig build')
    parser.add_argument('--configuration', choices=['Debug', 'Release'], required=True)
    parser.add_argument('--output-dir', type=Path, required=True, help='New folder outside the repository for raw trace/XML')
    parser.add_argument('--seconds', type=int, default=20, choices=range(5, 61), metavar='5..60')
    args = parser.parse_args()
    app = args.app.resolve(strict=True)
    with (app / 'Info.plist').open('rb') as file:
        info = plistlib.load(file)
    bundle, executable = info['CFBundleIdentifier'], info['CFBundleExecutable']
    if not re.fullmatch(r'[A-Za-z0-9_.-]+', bundle) or Path(executable).name != executable:
        parser.error('Invalid app bundle/executable identity')
    simulator = str(args.simulator).upper()
    devices = json.loads(command(['xcrun', 'simctl', 'list', 'devices', '--json']))
    matches = [device for runtime, group in devices['devices'].items() if '.iOS-' in runtime
               for device in group if device['udid'].upper() == simulator and device['state'] == 'Booted' and device.get('isAvailable')]
    if len(matches) != 1:
        parser.error('Select one booted, available standard iOS simulator')
    jobs = command(['xcrun', 'simctl', 'spawn', simulator, 'launchctl', 'list'])
    pids = [match.group(1) for line in jobs.splitlines()
            if (match := re.fullmatch(r'(\d+)\s+\S+\s+UIKitApplication:' + re.escape(bundle) + r'\[.*', line))]
    if len(pids) != 1 or int(pids[0]) == 0:
        parser.error('App is not uniquely running on the selected simulator')
    installed = Path(command(['xcrun', 'simctl', 'get_app_container', simulator, bundle, 'app']).strip())
    uuid_pattern = r'UUID: ([A-Fa-f0-9-]{36}) \(([^)]+)\)'
    built_ids = set(re.findall(uuid_pattern, command(['xcrun', 'dwarfdump', '--uuid', str(app / executable)])))
    installed_ids = set(re.findall(uuid_pattern, command(['xcrun', 'dwarfdump', '--uuid', str(installed / executable)])))
    if not built_ids or built_ids != installed_ids:
        parser.error('Installed executable UUIDs differ from the supplied build')
    output = args.output_dir.resolve()
    repo = Path(__file__).resolve().parents[2]
    if output == repo or repo in output.parents:
        parser.error('Keep raw traces outside the git working tree')
    output.mkdir(parents=False, exist_ok=False)
    metadata = {'simulator': simulator, 'device': matches[0]['name'], 'bundle': bundle,
                'configuration': args.configuration, 'configuration_source': 'caller; use the exact Bitrig output path',
                'executable_uuids': sorted(built_ids), 'requested_seconds': args.seconds}
    (output / 'capture.json').write_text(json.dumps(metadata, indent=2) + '\n')
    print(f'Recording {bundle} PID {pids[0]} on {simulator}; perform one synthetic flow now.\nOutput: {output}', flush=True)
    try:
        result = subprocess.run(['xcrun', 'xctrace', 'record', '--template', 'Time Profiler', '--device', simulator,
                                 '--attach', pids[0], '--time-limit', f'{args.seconds}s', '--no-prompt',
                                 '--output', str(output / 'runtime.trace')], capture_output=True, text=True,
                                timeout=args.seconds + 40)
    except subprocess.TimeoutExpired as error:
        # Timeout output can be bytes even with text=True; retain the failure evidence outside git.
        (output / 'record.log').write_text(''.join(
            value.decode('utf-8', errors='replace') if isinstance(value, bytes) else value or ''
            for value in (error.stdout, error.stderr)))
        raise
    (output / 'record.log').write_text(result.stdout + result.stderr)
    if result.returncode:
        raise ValueError(f'Trace record failed ({result.returncode}); inspect record.log')
    trace = str(output / 'runtime.trace')
    command(['xcrun', 'xctrace', 'export', '--input', trace, '--toc', '--output', str(output / 'toc.xml')])
    xml = output / 'profile.xml'
    command(['xcrun', 'xctrace', 'export', '--input', trace, '--xpath',
             '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]', '--output', str(xml)])
    summary = summarize(xml, executable, [value for value, _ in built_ids])
    (output / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n')
    print(f'Exported {summary["samples"]} samples; app symbols: {summary["app_symbolication"]}. Not a latency/FPS measurement.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError, KeyError, ET.ParseError) as error:
        print(f'Capture failed: {error}', file=sys.stderr)
        sys.exit(2)
