#!/usr/bin/env python3
"""Build a disposable export, leaving candidate sources and Bitrig state untouched."""
from pathlib import Path
import subprocess
import sys
import tarfile

source, output = map(lambda s: Path(s).resolve(), sys.argv[1:3])
output.mkdir(parents=True, exist_ok=False)
tree = output / 'source'
tree.mkdir()
archive = subprocess.run(['git', 'archive', 'HEAD'], cwd=source, check=True, capture_output=True).stdout
archive_path = output / 'source.tar'
archive_path.write_bytes(archive)
with tarfile.open(archive_path) as tf:
    tf.extractall(tree, filter='data')
xcodegen = '/Volumes/WorkspaceSSD/Development/Tools/memora-supervisor/xcodegen/2.46.0/bin/xcodegen'
subprocess.run([xcodegen, 'generate', '--spec', 'Project.json'], cwd=tree, check=True)
subprocess.run(['/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild', '-project', str(tree / 'Memora.xcodeproj'), '-scheme', 'Memora',
                '-configuration', 'Debug', '-destination', 'generic/platform=iOS Simulator',
                '-jobs', '4', '-derivedDataPath', str(output / 'DerivedData'),
                'ARCHS=arm64', 'ONLY_ACTIVE_ARCH=YES', 'CODE_SIGNING_ALLOWED=NO', 'build'],
               cwd=tree, check=True)
