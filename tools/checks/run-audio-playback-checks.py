#!/usr/bin/env python3
"""Check production playback reservations and enqueue callbacks without audio output."""
from pathlib import Path
import os
import subprocess
import tempfile

os.chdir(Path(__file__).resolve().parents[2])
source = Path('App/AudioPlayerService.swift').read_text()
enqueue = source[source.index('  private func enqueue('):source.index('  /// Wires the graph')]
ticker = source[source.index('  private func startTicker()'):source.rindex('\n}')]
with tempfile.TemporaryDirectory(prefix='memora-playback-', dir=os.environ.get('MEMORA_CHECK_ROOT')) as temporary:
    root = Path(temporary)
    production = root / 'ProductionEnqueue.swift'
    production.write_text('import AVFAudio\nimport Foundation\nextension PlaybackQueueFixture {\n' + enqueue + '''
  func start(_ audioFile: AVAudioFile, at frame: Int64 = 0) {
    file = audioFile
    isPlaying = true
    for segment in playbackSchedule.start(at: frame, length: audioFile.length,
                                          sampleRate: audioFile.processingFormat.sampleRate) {
      enqueue(segment, file: audioFile)
    }
  }
}
''' + 'extension PlaybackTickerFixture {\n' + ticker + '''
  func restartTicker() async {
    startTicker()
    try? await Task.sleep(for: .milliseconds(20))
    stopTicker()
    startTicker()
  }
  func cancelTicker() { stopTicker() }
}
''')
    binary = root / 'checks'
    subprocess.run(['swiftc', '-swift-version', '6', 'App/AudioPlaybackSchedule.swift',
                    'tools/checks/AudioPlaybackChecks.swift', str(production), '-o', str(binary)], check=True)
    subprocess.run([str(binary), str(root)], check=True, env=dict(os.environ, SWIFT_BACKTRACE='enable=no'))
