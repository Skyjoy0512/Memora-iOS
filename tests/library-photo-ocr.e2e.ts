import { copyFileSync, mkdirSync, unlinkSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { seedSummaryFixture } from './summary-fixture-helpers';
import { sql } from './sqlite-fixture-helpers';
import { requireRootMenu, tapControl } from './ui-helpers';

test('Library finds a record from an unopened photo and stops matching when the original disappears', { timeout: 180_000 }, async ({ app, device, screen }) => {
  const { database, fixture, title } = await seedSummaryFixture(app, device, screen);
  await device.closeApp();
  const photos = resolve(dirname(database), '../../..', 'Documents', 'Photos');
  mkdirSync(photos, { recursive: true });
  const name = fixture.id + '.jpg';
  const photo = join(photos, name);
  copyFileSync(join(import.meta.dirname, 'fixtures', 'photo-ocr-quartz.jpg'), photo);
  const record = { ...fixture, photoFileNames: [name] };
  const bytes = Buffer.from(JSON.stringify([record]), 'utf8').toString('hex');
  sql(database, `UPDATE documents SET data=X'${bytes}' WHERE key='memoraMeetings';`);
  expect(sql(database, "SELECT COUNT(*) FROM documents WHERE key='memora.mediaIndex.v1';")).toBe('0');

  await app.restart();
  await requireRootMenu(app, screen);
  await tapControl(screen.getByRole('button', { name: 'ファイルを検索', exact: true }));
  const search = screen.getByTestId('collection.search.input');
  await expect(search).toBeFocused();
  await search.fill('quartz');
  const match = screen.getByRole('button', { name: new RegExp('^' + title) }).first();
  await expect(match).toBeVisible({ timeout: 30_000 });
  const position = sql(database, "SELECT instr(upper(CAST(data AS TEXT)), 'QUARTZ') FROM documents WHERE key='memora.mediaIndex.v1';");
  expect(Number(position)).toBeGreaterThan(0);

  unlinkSync(photo);
  await search.fill('ledger');
  await expect(screen.getByText('見つかりませんでした', { exact: true }).first()).toBeVisible();
  await expect(match).not.toBeVisible();
});
