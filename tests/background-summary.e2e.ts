import { randomUUID } from 'node:crypto';
import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { seedSummaryFixture } from './summary-fixture-helpers';
import { sql } from './sqlite-fixture-helpers';
import { tapControl, tapTab, scrollToControl } from './ui-helpers';

// Presentation/restart only: a paused job must not call any model. OS scheduling
// and long-running inference need separate real-device validation.
test('paused background summary preserves text and offers explicit retry after restart', { timeout: 240_000 }, async ({ app, device, screen }) => {
  const { database, fixture, title, summary, raw } = await seedSummaryFixture(app, device, screen);
  const record = { ...fixture, status: { waitingForSummary: {} },
    transcript: fixture.transcript.map(segment => ({ ...segment, identificationStatus: 'manual' })) };
  const job = { id: randomUUID(), meetingID: record.id,
    choice: { builtIn: { _0: 'detailedOverview' } }, engineRawValue: 'local',
    llm: { provider: 'openAI', modelID: 'fixture-never-sent', supportsToolCalling: true },
    automaticallySelect: false, preferences: { method: 'fixed', length: 'standard', displayOrder: 'importance' },
    cloudDisclosureConfirmed: false, usesCloud: false, createdAt: fixture.createdAt, requiresUserRetry: true };
  await device.closeApp();
  for (const [key, value] of [['memoraMeetings', [record]], ['memoraPendingSummaryJobs', [job]]] as const) {
    const bytes = Buffer.from(JSON.stringify(value)).toString('hex');
    sql(database, `INSERT OR REPLACE INTO documents(key,data,updated_at) VALUES ('${key}',X'${bytes}',0);`);
  }
  const storedJobs = () => JSON.parse(sql(database, "SELECT CAST(data AS TEXT) FROM documents WHERE key='memoraPendingSummaryJobs';"));
  const storedRecord = () => JSON.parse(sql(database, "SELECT CAST(data AS TEXT) FROM documents WHERE key='memoraMeetings';"))[0];
  await app.restart();
  await tapTab(screen, 'ライブラリ');
  await tapControl(screen.getByRole('button', { name: new RegExp('^' + title) }).first());
  await scrollToControl(screen, screen.getByText('要約が途中で止まりました', { exact: true }));
  await expect(screen.getByText('要約が途中で止まりました', { exact: true })).toBeVisible();
  expect(storedJobs()).toHaveLength(1);
  expect(storedJobs()[0].requiresUserRetry).toBe(true);
  expect(storedJobs()[0].attemptStartedAt ?? null).toBe(null);
  await app.screenshot('background-summary-paused');
  await tapControl(screen.getByRole('button', { name: 'もう一度要約する', exact: true }));
  await expect(screen.getByTestId('summary.generate')).toBeVisible();
  expect(storedJobs()[0].attemptStartedAt ?? null).toBe(null);
  expect(storedRecord().summary).toBe(summary);
  expect(storedRecord().transcript[0].text).toBe(raw);
  await tapControl(screen.getByRole('button', { name: 'キャンセル', exact: true }));
  expect(storedJobs()).toHaveLength(1);
  expect(storedJobs()[0].id.toLowerCase()).toBe(job.id.toLowerCase());
  expect(storedJobs()[0].requiresUserRetry).toBe(true);
  expect(storedJobs()[0].attemptStartedAt ?? null).toBe(null);
  expect(storedRecord().summary).toBe(summary);
  expect(storedRecord().transcript[0].text).toBe(raw);
  await app.restart();
  await tapTab(screen, 'ライブラリ');
  await tapControl(screen.getByRole('button', { name: new RegExp('^' + title) }).first());
  await scrollToControl(screen, screen.getByText('要約が途中で止まりました', { exact: true }));
  await expect(screen.getByText('要約が途中で止まりました', { exact: true })).toBeVisible();
  expect(storedJobs()).toHaveLength(1);
  expect(storedJobs()[0].requiresUserRetry).toBe(true);
  expect(storedJobs()[0].attemptStartedAt ?? null).toBe(null);
});
