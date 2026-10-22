import { execFileSync } from 'node:child_process';
import { existsSync, realpathSync } from 'node:fs';
import { join, sep } from 'node:path';

export type FixtureDocumentKey = 'memoraLifeLogEntries' | 'memoraProjectSources.v2';

export function sql(database: string, statement: string) {
  return execFileSync('/usr/bin/sqlite3', ['-cmd', '.timeout 5000', database, statement],
    { encoding: 'utf8', timeout: 10_000, stdio: ['ignore', 'pipe', 'pipe'] }).trim();
}

// Identify only this scenario's UI-created UUID marker in one booted test
// simulator. A path must resolve inside that container; preview/device data is excluded.
export function isolatedDatabase(marker: string, bundleID: string, key: FixtureDocumentKey = 'memoraLifeLogEntries') {
  if (!/^[a-zA-Z0-9-]+$/.test(marker)) throw new Error('Invalid fixture marker');
  if (!['memoraLifeLogEntries', 'memoraProjectSources.v2'].includes(key)) throw new Error('Invalid fixture document');
  const listing = JSON.parse(execFileSync('xcrun', ['simctl', 'list', 'devices', 'available', '--json'], { encoding: 'utf8' }));
  const matches: string[] = [];
  for (const devices of Object.values(listing.devices) as any[][]) {
    for (const simulator of devices) {
      if (simulator.name !== 'iPhone 18 Pro Max' || simulator.state !== 'Booted') continue;
      try {
        const container = realpathSync(execFileSync('xcrun', ['simctl', 'get_app_container', simulator.udid, bundleID, 'data'],
          { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim());
        const path = join(container, 'Library', 'Application Support', 'Memora', 'memora.sqlite');
        if (!existsSync(path)) continue;
        const database = realpathSync(path);
        if (!database.startsWith(container + sep)) continue;
        if (sql(database, `SELECT instr(CAST(data AS TEXT), '${marker}') > 0 FROM documents WHERE key='${key}';`) === '1') matches.push(database);
      } catch { /* An unrelated simulator without the test record is not a target. */ }
    }
  }
  if (matches.length !== 1) throw new Error('Cannot uniquely identify the isolated fixture database');
  return matches[0];
}
