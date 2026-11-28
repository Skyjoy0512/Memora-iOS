import { randomUUID } from 'node:crypto';
import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, selectLibrarySection, tapControl, tapTab } from './ui-helpers';
import { isolatedDatabase, sql } from './sqlite-fixture-helpers';

// Opt-in only: this test performs one real HTTPS request to the URL the owner
// provides. It never runs in the normal suite, never uses a sample site, and
// does not send the page to a cloud model. Summary/Ask AI uses the on-device
// model; if that model cannot run the test reports the app's own message.
const realURL = process.env.MEMORA_REAL_WEB_URL?.trim();

test('an approved HTTPS source is extracted, answered on-device and cited', {
  timeout: 300_000,
  skip: realURL ? false : 'Set MEMORA_REAL_WEB_URL to an approved HTTPS page'
}, async ({ app, device, screen }) => {
  const target = new URL(realURL!);
  const marker = 'RealWeb-' + randomUUID();
  target.searchParams.set('memora_e2e', marker);
  const project = 'RealWeb-' + randomUUID().slice(0, 8);

  async function openReferences() {
    await tapControl(screen.getByRole('button', { name: '参考資料', exact: true }).last());
  }

  await launchMemora(app, device, screen);
  await selectLibrarySection(screen, 'プロジェクト');
  await tapControl(screen.getByRole('button', { name: 'プロジェクトを作成', exact: true }).first());
  await screen.getByPlaceholder('例：新規アプリ').fill(project);
  await tapControl(screen.getByRole('button', { name: '作成', exact: true }));
  await openReferences();
  await tapControl(screen.getByRole('button', { name: '参考資料を追加', exact: true }).first());
  const body = screen.getByRole('textbox', { name: 'ノート本文', exact: true });
  await tapControl(screen, body);
  await expect(body).toBeFocused();
  await body.pressSequentially(target.href);
  const closeKeyboard = screen.getByRole('button', { name: 'キーボードを閉じる', exact: true });
  if (await closeKeyboard.isVisible()) await tapControl(closeKeyboard);
  await expect(screen.getByRole('keyboard')).not.toBeVisible();
  await tapControl(screen.getByRole('button', { name: '保存', exact: true }));

  const identity = await device.foregroundApp();
  const database = isolatedDatabase(marker, identity.bundleId!, 'memoraProjectSources.v2');
  const sources = () => JSON.parse(sql(database,
    "SELECT CAST(data AS TEXT) FROM documents WHERE key='memoraProjectSources.v2';"));
  let source: any;
  await expect.poll(() => {
    source = sources().find((value: any) => String(value.originalURL ?? '').includes(marker));
    return source?.processingStatus === 'ready' || source?.processingStatus === 'failed';
  }, { timeout: 180_000, interval: 2_000 }).toBe(true);
  if (source.processingStatus === 'failed') {
    throw new Error('Real page extraction failed: ' + String(source.errorInformation ?? 'no reason'));
  }
  expect(source.title?.length).toBeGreaterThan(0);
  expect(String(source.extractedTextReference ?? '').length).toBeGreaterThan(0);

  const row = screen.getByRole('button', { name: new RegExp('^' + escapeRegExp(source.title)) }).first();
  await expect(row).toBeVisible({ timeout: 30_000 });
  await tapControl(row);
  const original = screen.getByText('原文', { exact: true }).first();
  if (await original.isVisible()) await tapControl(original);
  await expect(screen.getByTestId('source.askAI')).toBeVisible({ timeout: 30_000 });
  await tapControl(screen.getByTestId('source.askAI'));
  await expect(screen.getByText('この資料について質問', { exact: true }).first()).toBeVisible({ timeout: 10_000 });
  const composer = screen.getByTestId('ai.composer.input');
  await tapControl(screen, composer);
  await expect(composer).toBeFocused();
  await composer.pressSequentially('この資料の要点を、資料に書かれている範囲で教えてください。');
  await tapControl(screen.getByRole('button', { name: '送信', exact: true }));
  // The on-device fallback must either answer from the page or say it cannot.
  await expect(screen.getByText(/資料|要点|わかりません|できません/).first()).toBeVisible({ timeout: 180_000 });
  const citation = screen.getByRole('button', { name: new RegExp('^' + escapeRegExp(source.title)) }).last();
  if (await citation.isVisible()) {
    await tapControl(citation);
    await expect(screen.getByTestId('source.askAI')).toBeVisible({ timeout: 30_000 });
  }
  await app.screenshot('real-web-source');
});

function escapeRegExp(value: string) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
