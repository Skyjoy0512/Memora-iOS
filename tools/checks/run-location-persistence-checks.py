#!/usr/bin/env python3
"""Production station/visit/inbox paths with real SQLite; no location or network requests."""
from pathlib import Path
import os
import subprocess
import tempfile

os.chdir(Path(__file__).resolve().parents[2])
source = Path('App/AutoLocationLogger.swift').read_text()
methods = source[source.index('  @discardableResult\n  private func recordStationPass('):source.index('  // MARK: - Excluded places')]
result = source[source.index('  enum DebugStationResult:'):source.index('  private static let stationRepeatWindow:')]
assert 'requiresAlwaysAuthorization: false' in source
assert 'locationGeneration = UUID()' in source[source.index('  private func stopMonitoring()'):source.index('  // MARK: - Authorization')]
assert 'locationGeneration = UUID()' in source[source.index('  private func handleAuthorizationChange('):source.index('  // MARK: - Locations')]
# Only the settings store is redirected, leaving the production decisions intact.
methods = methods.replace('UserDefaults.standard', 'Self.defaults')
with tempfile.TemporaryDirectory(prefix='memora-location-', dir=os.environ.get('MEMORA_CHECK_ROOT')) as temporary:
    root = Path(temporary)
    production = root / 'ProductionLocation.swift'
    production.write_text('import Foundation\nimport CoreLocation\nextension AutoLocationLogger {\n' + result + methods + '''
  func station(_ location: CLLocation, debug: Bool = false) async -> DebugStationResult {
    await recordStationPass(at: location, requiresAlwaysAuthorization: !debug)
  }
  func visit(_ location: CLLocation) async {
    await recordVisit(at: location, arrival: .now.addingTimeInterval(-1200), departure: .now)
  }
}
''')
    binary = root / 'checks'
    subprocess.run(['swiftc', 'App/LocalStore.swift', 'App/LocalSaveFailure.swift',
                    'Shared/MemoraIcon.swift', 'App/LifeLogEntry.swift', 'App/LifeLogSource.swift',
                    'App/LifeLogKind.swift', 'App/LifeLogOrigin.swift', 'App/RecordPrivacy.swift',
                    'App/SummarySensitivity.swift', 'tools/checks/LocationPersistenceChecks.swift',
                    str(production), '-o', str(binary)], check=True)
    subprocess.run([str(binary), str(root)], check=True, env=dict(os.environ, SWIFT_BACKTRACE='enable=no'))
