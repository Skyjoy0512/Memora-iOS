import { randomUUID } from 'node:crypto';
import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, openSidebarSearch, scrollToControl, tapControl, tapTab } from './ui-helpers';
import { isolatedDatabase, sql } from './sqlite-fixture-helpers';

test('journal SQLite failures retain drafts and records, then recover through the UI', { timeout: 360_000 }, async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  const marker = 'memora-journal-failure-' + randomUUID();
  async function newMemo(title: string, detail: string) {
    // The memo link now opens the note editor; the journal's own sheet is the
    // one that writes a life-log entry.
    await tapTab(screen, 'ジャーナル');
    // A day without entries shows the add action directly; a populated day
    // keeps it at the end of a lazy timeline.
    const emptyDay = screen.getByRole('button', { name: /、記録なし$/ }).first();
    await tapControl(screen, emptyDay);
    await tapControl(screen.getByRole('button', { name: '記録を追加', exact: true }).first());
    await expect(screen.getByText('ライフログを追加', { exact: true })).toBeVisible();
    await screen.getByRole('textbox', { name: 'メモのタイトル', exact: true }).fill(title);
    await screen.getByRole('textbox', { name: 'ひとことや背景', exact: true }).fill(detail);
  }
  async function saveMemo() {
    await tapControl(screen, screen.getByRole('button', { name: '追加', exact: true }));
    await expect(screen.getByText('ライフログを追加', { exact: true })).not.toBeVisible();
  }
  async function searchAndOpen(title: string) {
    await tapTab(screen, 'ジャーナル');
    await openSidebarSearch(screen);
    await screen.getByPlaceholder('ジャーナルを検索').fill(title);
    await tapControl(screen, screen.getByText(title, { exact: true }).first());
    await expect(screen.getByLabel('その他')).toBeVisible();
  }
  await newMemo(marker, 'Isolated database identity');
  await saveMemo();
  const identity = await device.foregroundApp();
  if (identity.bundleId !== 'app.bitrig.new.811eee03-bad9-4f5e-9d1d-d2820c1e93b4') throw new Error('Unexpected application');
  const database = isolatedDatabase(marker, identity.bundleId);
  const triggers = new Set<string>();
  function failWrites(key: 'memoraLifeLogEntries' | 'memoraLifeLogTrash') {
    const name = 'memora_e2e_' + randomUUID().replaceAll('-', '');
    sql(database, `CREATE TRIGGER ${name} BEFORE INSERT ON documents WHEN NEW.key='${key}' BEGIN SELECT RAISE(ABORT, 'isolated E2E journal failure'); END;`);
    triggers.add(name);
    return () => { sql(database, `DROP TRIGGER ${name};`); triggers.delete(name); };
  }
  try {
    await newMemo('Retained journal draft', 'Draft survives the failed transaction');
    let recover = failWrites('memoraLifeLogEntries');
    await tapControl(screen, screen.getByRole('button', { name: '追加', exact: true }));
    await expect(screen.getByText('保存できませんでした', { exact: true }).last()).toBeVisible();
    await tapControl(screen, screen.getByRole('button', { name: '閉じる', exact: true }).last());
    await expect(screen.getByRole('textbox', { name: 'メモのタイトル', exact: true })).toHaveValue('Retained journal draft');
    await expect(screen.getByRole('textbox', { name: 'ひとことや背景', exact: true })).toHaveValue('Draft survives the failed transaction');
    await app.screenshot('journal-create-failure-retains-input');
    recover();
    await saveMemo();
    await app.restart();
    await searchAndOpen('Retained journal draft');
    await tapControl(screen, screen.getByLabel('その他'));
    await tapControl(screen, screen.getByRole('button', { name: '編集', exact: true }));
    await expect(screen.getByText('記録を編集', { exact: true })).toBeVisible();
    await screen.getByRole('textbox', { name: 'タイトル', exact: true }).fill('Recovered journal edit');
    await screen.getByRole('textbox', { name: '本文', exact: true }).fill('Edit survives the failed transaction');
    recover = failWrites('memoraLifeLogEntries');
    await tapControl(screen, screen.getByRole('button', { name: '保存', exact: true }));
    await expect(screen.getByText('保存できませんでした', { exact: true }).last()).toBeVisible();
    await tapControl(screen, screen.getByRole('button', { name: '閉じる', exact: true }).last());
    await expect(screen.getByRole('textbox', { name: 'タイトル', exact: true })).toHaveValue('Recovered journal edit');
    await expect(screen.getByRole('textbox', { name: '本文', exact: true })).toHaveValue('Edit survives the failed transaction');
    await app.screenshot('journal-edit-failure-retains-input');
    recover();
    await tapControl(screen, screen.getByRole('button', { name: '保存', exact: true }));
    await expect(screen.getByText('記録を編集', { exact: true })).not.toBeVisible();
    await app.restart();
    await searchAndOpen('Recovered journal edit');
    recover = failWrites('memoraLifeLogTrash');
    await tapControl(screen, screen.getByLabel('その他'));
    await tapControl(screen, screen.getByRole('button', { name: '削除', exact: true }));
    await expect(screen.getByRole('group', { name: 'この記録を削除しますか？', exact: true })).toBeVisible();
    await tapControl(screen, screen.getByRole('button', { name: '削除', exact: true }));
    await expect(screen.getByText('削除できませんでした', { exact: true })).toBeVisible();
    await tapControl(screen, screen.getByRole('button', { name: '閉じる', exact: true }).last());
    await expect(screen.getByText('Edit survives the failed transaction', { exact: true }).last()).toBeVisible();
    await expect(screen.getByLabel('その他')).toBeVisible();
    await app.screenshot('journal-delete-failure-keeps-detail');
    recover();
    await tapControl(screen, screen.getByLabel('その他'));
    await tapControl(screen, screen.getByRole('button', { name: '削除', exact: true }));
    await expect(screen.getByRole('group', { name: 'この記録を削除しますか？', exact: true })).toBeVisible();
    await tapControl(screen, screen.getByRole('button', { name: '削除', exact: true }));
    await expect(screen.getByText('見つかりませんでした', { exact: true })).toBeVisible();
    await app.restart();
    await tapTab(screen, 'ジャーナル');
    await openSidebarSearch(screen);
    await screen.getByPlaceholder('ジャーナルを検索').fill('Recovered journal edit');
    await expect(screen.getByText('見つかりませんでした', { exact: true })).toBeVisible();
  } finally {
    for (const name of triggers) sql(database, `DROP TRIGGER IF EXISTS ${name};`);
  }
});
