import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, tapControl, tapTab } from './ui-helpers';
import { seedSummaryFixture } from './summary-fixture-helpers';
import { sql } from './sqlite-fixture-helpers';
import { randomUUID } from 'node:crypto';

test('main destinations retain their own bottom controls and Settings stays reachable', { timeout: 180_000 }, async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  for (const destination of ['ライブラリ', 'ジャーナル', 'Ask AI', 'マーケットプレイス']) {
    await tapTab(screen, destination);
    const composer = screen.getByTestId('ai.composer.input');
    const capture = screen.getByRole('button', { name: '追加メニュー', exact: true });
    if (destination === 'マーケットプレイス') {
      await expect(composer).not.toBeVisible();
      await expect(screen.getByTestId('collection.search.input')).toBeVisible();
    } else {
      await expect(composer).toBeVisible();
    }
    if (destination === 'Ask AI' || destination === 'マーケットプレイス') {
      await expect(capture).not.toBeVisible();
    } else {
      await expect(capture).toBeVisible();
    }
    await app.screenshot(`uiux-${destination}`);
  }
  await tapControl(screen.getByLabel('メニュー').first());
  await tapControl(screen.getByTestId('sidebar.settings'));
  await expect(screen.getByTestId('settings.profile')).toBeVisible();
  await expect(screen.getByTestId('settings.category.account')).toBeVisible();
  await tapControl(screen.getByRole('button', { name: '閉じる', exact: true }));
  await expect(screen.getByTestId('collection.search.input')).toBeVisible();
});

test('catalog detail and add controls remain separate and search returns to the catalog', { timeout: 150_000 }, async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapTab(screen, 'マーケットプレイス');
  const row = screen.getByTestId('marketplace.item.service:gmail');
  const add = screen.getByRole('button', { name: 'Gmailを追加・接続', exact: true });
  await expect(row).toBeVisible();
  await expect(add).toBeVisible();
  const rowBox = await row.boundingBox();
  const addBox = await add.boundingBox();
  if (!rowBox || !addBox) throw new Error('Catalog controls have no frame');
  expect(addBox.width).toBeGreaterThanOrEqual(44);
  expect(addBox.height).toBeGreaterThanOrEqual(44);
  expect(rowBox.x + rowBox.width).toBeLessThanOrEqual(addBox.x);
  await tapControl(row);
  await expect(screen.getByText('情報', { exact: true }).first()).toBeVisible();
  await tapControl(screen.getByRole('button', { name: '閉じる', exact: true }));
  const search = screen.getByTestId('collection.search.input');
  await tapControl(search);
  await search.fill('Notion');
  await expect(screen.getByRole('button', { name: /^Notion、/ })).toBeVisible();
  await expect(screen.getByTestId('marketplace.item.service:gmail')).not.toBeVisible();
  await tapControl(screen.getByTestId('collection.search.cancel'));
  await expect(row).toBeVisible();
});

test('document hierarchy, person details and contextual questions retain real content', { timeout: 180_000 }, async ({ app, device, screen }) => {
  const { database } = await seedSummaryFixture(app, device, screen);
  await expect(screen.getByTestId('ai.composer.input')).toHaveValue('この記録に質問');
  await device.closeApp();
  const title = '検証用：来週の打ち合わせと担当者への確認事項';
  const body = '承認されるまで公開せず、担当者と次の確認日を記録します。';
  const name = '表示検証用・佐藤さん';
  const date = Date.now() / 1000 - 978307200;
  for (const [key, records] of [
    ['memoraDocuments', [{ id: randomUUID(), title, kind: 'document', markdown: body, slides: [], createdAt: date, updatedAt: date }]],
    ['memoraPeople', [{ id: randomUUID(), name, note: '次回の打ち合わせで条件を確認する' }]],
  ] as const) {
    const existing = sql(database, `SELECT CAST(data AS TEXT) FROM documents WHERE key='${key}';`);
    expect(existing === '' || JSON.parse(existing).length === 0).toBe(true);
    const hex = Buffer.from(JSON.stringify(records), 'utf8').toString('hex');
    sql(database, `INSERT OR REPLACE INTO documents (key,data,updated_at) VALUES ('${key}',X'${hex}',${date});`);
  }
  await app.restart();
  const openExtra = async (label: string) => {
    await tapControl(screen.getByLabel('メニュー').first());
    await tapControl(screen.getByTestId('sidebar.more'));
    await tapControl(screen.getByRole('button', { name: label, exact: true }));
  };
  await openExtra('資料');
  const document = screen.getByText(title, { exact: true });
  const preview = screen.getByText(body, { exact: true });
  await expect(document).toBeVisible();
  await expect(preview).toBeVisible();
  const titleBox = await document.boundingBox();
  const previewBox = await preview.boundingBox();
  if (!titleBox || !previewBox) throw new Error('Document text has no frame');
  expect(titleBox.y + titleBox.height).toBeLessThanOrEqual(previewBox.y);
  await app.screenshot('uiux-document-list');
  await openExtra('人物');
  await tapControl(screen.getByText(name, { exact: true }));
  await expect(screen.getByText('次回の打ち合わせで条件を確認する', { exact: true }).last()).toBeVisible();
  await expect(screen.getByRole('button', { name: `「${name}」についてAIに聞く`, exact: true })).toBeVisible();
  await app.screenshot('uiux-person-detail');
});
