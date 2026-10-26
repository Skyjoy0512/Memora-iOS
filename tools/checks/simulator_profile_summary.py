#!/usr/bin/env python3
"""Summarize an Instruments time-profile export without treating weights as latency."""
import argparse
from collections import Counter
import json
from pathlib import Path
import uuid
import xml.etree.ElementTree as ET


def summarize(path, app_name, expected_uuids):
    path = Path(path)
    if path.stat().st_size > 64 * 1024 * 1024:
        raise ValueError('Profile XML exceeds 64 MiB')
    data = path.read_bytes()
    if b'<!DOCTYPE' in data or b'<!ENTITY' in data:
        raise ValueError('XML declarations are not supported')
    root = ET.fromstring(data)
    nodes = root.findall('node')
    if len(nodes) != 1:
        raise ValueError('Export exactly one run/table')
    node = nodes[0]
    schema = node.find('schema')
    expected_columns = ['time', 'thread', 'process', 'core', 'thread-state', 'weight', 'stack']
    if schema is None or schema.get('name') != 'time-profile' or [c.findtext('mnemonic') for c in schema.findall('col')] != expected_columns:
        raise ValueError('Unsupported time-profile schema')
    ids = {}
    for element in node.iter():
        identifier = element.get('id')
        if identifier:
            if identifier in ids:
                raise ValueError('Duplicate Instruments ID')
            ids[identifier] = element

    def resolve(element):
        seen = set()
        while element.get('ref'):
            identifier = element.get('ref')
            if identifier in seen or identifier not in ids:
                raise ValueError('Unresolved or cyclic Instruments reference')
            seen.add(identifier)
            element = ids[identifier]
        return element

    def number(element):
        value = int(resolve(element).text)
        if not 0 <= value <= 2**63 - 1:
            raise ValueError('Invalid sample weight/time')
        return value

    rows = node.findall('row')
    if not rows or len(rows) > 500_000:
        raise ValueError('Empty or excessive time-profile samples; no performance conclusion')
    expected_uuids = {str(uuid.UUID(value)).upper() for value in expected_uuids}
    if not expected_uuids:
        raise ValueError('Provide UUIDs from the exact installed app executable')
    leaves, inclusive, states = Counter(), Counter(), Counter()
    total = main = app_weight = ambiguous = missing_stack = 0
    first = last = None
    observed_uuids = set()
    for row in rows:
        columns = list(row)
        if len(columns) != len(expected_columns):
            raise ValueError('Unexpected profile row shape')
        if resolve(columns[2]).get('fmt', '').split(' (')[0] != app_name:
            raise ValueError('Mixed or unexpected process in profile')
        timestamp, weight = number(columns[0]), number(columns[5])
        if weight == 0:
            raise ValueError('Zero sample weight')
        first = timestamp if first is None else min(first, timestamp)
        last = timestamp if last is None else max(last, timestamp)
        total += weight
        thread = resolve(columns[1])
        if thread.get('fmt', '').startswith('Main Thread '):
            main += weight
        states[resolve(columns[4]).get('fmt', 'unknown')] += weight
        stack = resolve(columns[6])
        frames = [resolve(frame) for frame in stack.findall('frame')]
        if not frames:
            missing_stack += weight
            continue
        leaves[frames[0].get('name') or '<unresolved>'] += weight
        names, has_ambiguous = set(), False
        for frame in frames:
            binary = frame.find('binary')
            if binary is None:
                raise ValueError('Frame has no binary')
            binary = resolve(binary)
            if binary.get('name') not in {app_name, app_name + '.debug.dylib'}:
                continue
            image_uuid = str(uuid.UUID(binary.get('UUID', ''))).upper()
            observed_uuids.add(image_uuid)
            if image_uuid not in expected_uuids:
                raise ValueError('Profile/app executable UUID mismatch')
            name = frame.get('name', '')
            if not name or name.startswith(('0x', '<')) or name == '???':
                has_ambiguous = True
            else:
                names.add(name)
        if names or has_ambiguous:
            app_weight += weight
        if has_ambiguous:
            ambiguous += weight
        # Count recursive/inlined occurrences once per stack, not once per frame.
        for name in names:
            inclusive[name] += weight
    if not observed_uuids:
        raise ValueError('No app frames; cannot verify app symbolication')

    def top(counter):
        return [{'symbol': name, 'sample_weight_ms': round(value / 1e6, 3)}
                for name, value in sorted(counter.items(), key=lambda item: (-item[1], item[0]))[:15]]

    return {'schema': 'memora.time-profile-summary.v1', 'samples': len(rows),
            'app_binary_uuids': sorted(observed_uuids),
            'sample_span_seconds': round((last - first) / 1e9, 6),
            'total_sample_weight_ms': round(total / 1e6, 3),
            'main_thread_sample_weight_ms': round(main / 1e6, 3),
            'app_inclusive_sample_weight_ms': round(app_weight / 1e6, 3),
            'ambiguous_app_sample_weight_ms': round(ambiguous / 1e6, 3),
            'missing_backtrace_sample_weight_ms': round(missing_stack / 1e6, 3),
            'app_symbolication': 'partial' if ambiguous or missing_stack else 'named',
            'state_sample_weight_ms': {key: round(value / 1e6, 3) for key, value in sorted(states.items())},
            'top_leaves': top(leaves), 'top_app_inclusive': top(inclusive),
            'limitations': 'Statistical sample weights; not wall latency, FPS, body counts, exact CPU occupancy, memory, or iPhone hardware performance. Inclusive weights overlap; deduplicated/unresolved app symbols are excluded from named totals.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xml', type=Path)
    parser.add_argument('--app-name', default='Memora')
    parser.add_argument('--expected-uuid', action='append', required=True)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    try:
        result = summarize(args.xml, args.app_name, args.expected_uuid)
    except (ValueError, OSError, ET.ParseError, TypeError) as error:
        parser.exit(2, f'Profile rejected: {error}\n')
    encoded = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if args.output:
        args.output.write_text(encoded)
    print(encoded, end='')


if __name__ == '__main__':
    main()
