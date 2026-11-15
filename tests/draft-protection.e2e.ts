import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { seedSummaryFixture } from './summary-fixture-helpers';
import { scrollToControl, tapControl, tapTab } from './ui-helpers';
import { sql } from './sqlite-fixture-helpers';

// The UUID marker in seedSummaryFixture identifies a fresh dedicated test
// simulator. Invalid bytes are never written into Bitrig's preview or a device.
test('an unreadable summary draft blocks editing and retains its original bytes', { timeout: 180_000 }, async ({ app, device, screen }) => {
  const { database, fixture, title, summary } = await seedSummaryFixture(app, device, screen);
  const key = `draft.meeting.${fixture.id.toUpperCase()}.summary`;
  await device.closeApp();
  sql(database, `INSERT OR REPLACE INTO documents (key,data,updated_at) VALUES ('${key}',X'01FF',0);`);
  await app.restart();
  await tapTab(screen, 'ライブラリ');
  await tapControl(screen.getByRole('button', { name: new RegExp('^' + title) }).first());
  const notice = '下書きを読み込めなかったため、上書きを止めています。画面を閉じて、もう一度開いてください。';
  await expect(screen.getByText(notice, { exact: true })).toBeVisible();
  await tapControl(screen.getByRole('button', { name: 'OK', exact: true }));
  const paragraph = screen.getByRole('button', { name: '予算は10万円ではなく12万円。承認された場合だけ来週実施する。', exact: true });
  await scrollToControl(screen, paragraph);
  await tapControl(paragraph);
  await expect(screen.getByRole('textbox', { name: '本文', exact: true })).not.toBeVisible();
  expect(sql(database, `SELECT hex(data) FROM documents WHERE key='${key}';`)).toBe('01FF');
  const records = JSON.parse(sql(database, "SELECT CAST(data AS TEXT) FROM documents WHERE key='memoraMeetings';"));
  expect(records[0].summary).toBe(summary);
  await app.screenshot('unreadable-draft-preserved');
});

test('an unreadable composer draft protects the store during launch', { timeout: 180_000 }, async ({ app, device, screen }) => {
  const { database, summary } = await seedSummaryFixture(app, device, screen);
  await device.closeApp();
  const key = 'draft.composer.question';
  sql(database, `INSERT OR REPLACE INTO documents (key,data,updated_at) VALUES ('${key}',X'01FF',0);`);
  await app.restart();
  await expect(screen.getByTestId('composer.recovery.open')).toBeVisible();
  await expect(screen.getByTestId('ai.composer.input')).toBeDisabled();
  expect(sql(database, `SELECT hex(data) FROM documents WHERE key='${key}';`)).toBe('01FF');
  const records = JSON.parse(sql(database, "SELECT CAST(data AS TEXT) FROM documents WHERE key='memoraMeetings';"));
  expect(records[0].summary).toBe(summary);
  await tapControl(screen.getByTestId('composer.recovery.open'));
  await expect(screen.getByText('前回の下書きを読み込めないため、Ask AIの入力を保護しています。', { exact: true })).toBeVisible();
  expect(sql(database, `SELECT hex(data) FROM documents WHERE key='${key}';`)).toBe('01FF');
  await app.restart();
  await expect(screen.getByTestId('composer.recovery.open')).toBeVisible();
  await expect(screen.getByTestId('ai.composer.input')).toBeDisabled();
  expect(sql(database, `SELECT hex(data) FROM documents WHERE key='${key}';`)).toBe('01FF');
  expect(JSON.parse(sql(database, "SELECT CAST(data AS TEXT) FROM documents WHERE key='memoraMeetings';"))[0].summary).toBe(summary);
  await app.screenshot('unreadable-composer-store-protection');
});
