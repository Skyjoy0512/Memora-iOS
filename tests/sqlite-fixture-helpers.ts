import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
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
      if (!['iPhone 18 Pro Max', 'iPhone 18 Pro'].includes(simulator.name) || simulator.state !== 'Booted') continue;
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

const meetingRowPrefix = 'memora.meeting.';
const archiveManifestKey = 'memora.meetings.archive.v1';

/**
 * The records as the app stores them. Once the archive exists each record is
 * its own document (a SHA-256 of the payload followed by the payload) and the
 * manifest lists the order; before that they are one collection document. A
 * fixture that seeds or inspects records has to speak both.
 */
export function readMeetings(database: string): any[] | null {
  const manifest = sql(database,
    `SELECT CAST(data AS TEXT) FROM documents WHERE key='${archiveManifestKey}';`);
  if (!manifest) {
    const legacy = sql(database, "SELECT CAST(data AS TEXT) FROM documents WHERE key='memoraMeetings';");
    return legacy ? JSON.parse(legacy) : null;
  }
  const ids: string[] = JSON.parse(manifest).ids;
  const rows = sql(database,
    `SELECT key || ' ' || hex(data) FROM documents WHERE key >= '${meetingRowPrefix}' AND key < 'memora.meeting/';`);
  const records = new Map<string, any>();
  for (const line of rows.split('\n')) {
    if (!line) continue;
    const space = line.indexOf(' ');
    const key = line.slice(0, space);
    const payload = Buffer.from(line.slice(space + 1), 'hex').subarray(32);
    records.set(key.slice(meetingRowPrefix.length), JSON.parse(payload.toString('utf8')));
  }
  return ids.map((id) => records.get(String(id).toLowerCase())).filter(Boolean);
}

/** Replaces every stored record, in the archive format the app reads. */
export function writeMeetings(database: string, records: any[]) {
  const statements = [
    `DELETE FROM documents WHERE key >= '${meetingRowPrefix}' AND key < 'memora.meeting/';`,
    `DELETE FROM documents WHERE key='${archiveManifestKey}';`,
  ];
  const ids: string[] = [];
  for (const record of records) {
    const payload = Buffer.from(JSON.stringify(record));
    const document = Buffer.concat([createHash('sha256').update(payload).digest(), payload]);
    ids.push(String(record.id));
    statements.push(`INSERT OR REPLACE INTO documents(key,data,updated_at) VALUES ('${meetingRowPrefix}${String(record.id).toLowerCase()}',X'${document.toString('hex')}',0);`);
  }
  const manifest = Buffer.from(JSON.stringify({ schemaVersion: 1, ids }));
  statements.push(`INSERT OR REPLACE INTO documents(key,data,updated_at) VALUES ('${archiveManifestKey}',X'${manifest.toString('hex')}',0);`);
  sql(database, statements.join(' '));
}
