import { randomUUID } from 'node:crypto';
import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, tapControl, tapTab, scrollToControl } from './ui-helpers';
import { isolatedDatabase, sql } from './sqlite-fixture-helpers';

test('project source notes retain failed creates and edits, persist drafts, and recover after restart', { timeout: 360_000 }, async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  const marker = 'source-recovery-' + randomUUID();
  const project = 'SourceRecovery-' + randomUUID().slice(0, 8);
  const title = screen.getByRole('textbox', { name: 'タイトル', exact: true });
  const body = screen.getByRole('textbox', { name: 'メモ本文', exact: true });
  const sourceAdd = screen.getByRole('button', { name: 'ソースを追加', exact: true }).first();
  const triggers = new Set<string>();
  let database: string | undefined;
  const reveal = (control: any) => scrollToControl(screen, control, { minimumY: 140, maximumY: 850 });
  async function closeKeyboard() {
    const close = screen.getByRole('button', { name: 'キーボードを閉じる', exact: true });
    if (await close.isVisible()) await tapControl(close);
    await expect(screen.getByRole('keyboard')).not.toBeVisible();
  }
  async function fillNote(name: string, text: string) {
    await reveal(title); await title.fill(name); await closeKeyboard();
    await reveal(body); await body.fill(text); await closeKeyboard();
  }
  async function saveNote() {
    const save = screen.getByRole('button', { name: 'メモを保存', exact: true });
    await reveal(save); await tapControl(save);
  }
  async function reopenProject() {
    await tapTab(screen, 'ライブラリ');
    await tapControl(screen.getByRole('button', { name: 'プロジェクト', exact: true }));
    await tapControl(screen.getByText(project, { exact: true }).first());
    await tapControl(screen.getByRole('button', { name: 'ソース', exact: true }));
  }
  async function openNote(name: string) {
    const row = screen.getByText(name, { exact: true }).first();
    await reveal(row); await tapControl(row);
  }
  function failSourceWrites() {
    if (!database) throw new Error('Fixture database not identified');
    const name = 'memora_e2e_' + randomUUID().replaceAll('-', '');
    sql(database, `CREATE TRIGGER ${name} BEFORE INSERT ON documents WHEN NEW.key='memoraProjectSources.v2' BEGIN SELECT RAISE(ABORT, 'isolated source failure'); END;`);
    triggers.add(name);
    return () => { sql(database!, `DROP TRIGGER ${name};`); triggers.delete(name); };
  }
  try {
    await tapControl(screen.getByRole('button', { name: 'プロジェクト', exact: true }));
    await tapControl(screen.getByRole('button', { name: 'プロジェクトを作成', exact: true }).first());
    await screen.getByPlaceholder('例：新規アプリ').fill(project);
    await tapControl(screen.getByRole('button', { name: '作成', exact: true }));
    await tapControl(screen.getByRole('button', { name: 'ソース', exact: true }));
    await tapControl(sourceAdd);
    await expect(screen.getByText('ファイルは50MBまで。録音・音声取り込みは右上の＋からも始められます。', { exact: true })).toBeVisible();
    await fillNote(marker, 'Isolated source database identity');
    await saveNote();
    await expect(body).toHaveValue('');
    await tapControl(screen.getByRole('button', { name: '閉じる', exact: true }));
    const identity = await device.foregroundApp();
    if (identity.bundleId !== 'app.bitrig.new.811eee03-bad9-4f5e-9d1d-d2820c1e93b4') throw new Error('Unexpected app');
    database = isolatedDatabase(marker, identity.bundleId, 'memoraProjectSources.v2');
    await tapControl(sourceAdd);
    await fillNote('Retained source draft', 'Body retained after actual SQLite failure');
    let recover = failSourceWrites();
    await saveNote();
    await expect(screen.getByText('保存できませんでした。', { exact: true })).toBeVisible();
    await reveal(title); await expect(title).toHaveValue('Retained source draft');
    await reveal(body); await expect(body).toHaveValue('Body retained after actual SQLite failure');
    await app.screenshot('source-create-failure-retains-draft');
    recover();
    // Closing/reopening and a process restart must retain both fields, not just body.
    await tapControl(screen.getByRole('button', { name: '閉じる', exact: true }));
    await app.restart(); await reopenProject(); await tapControl(sourceAdd);
    await reveal(title); await expect(title).toHaveValue('Retained source draft');
    await reveal(body); await expect(body).toHaveValue('Body retained after actual SQLite failure');
    await saveNote(); await expect(body).toHaveValue('');
    await tapControl(screen.getByRole('button', { name: '閉じる', exact: true }));
    await expect(screen.getByText('本文解析済み', { exact: true }).first()).toBeVisible();
    await openNote('Retained source draft');
    await tapControl(screen.getByRole('button', { name: 'その他', exact: true }));
    await tapControl(screen.getByRole('button', { name: 'メモを編集', exact: true }));
    await title.fill('Recovered source edit'); await body.fill('Edited body survives failed save');
    await device.setAppearance('dark');
    recover = failSourceWrites();
    await tapControl(screen.getByRole('button', { name: '保存', exact: true }));
    await expect(screen.getByText('保存できませんでした。開き直して確認してください。', { exact: true })).toBeVisible();
    await expect(title).toHaveValue('Recovered source edit');
    await expect(body).toHaveValue('Edited body survives failed save');
    await app.screenshot('source-edit-failure-retains-draft');
    recover();
    await tapControl(screen.getByRole('button', { name: 'キャンセル', exact: true }));
    await app.restart(); await reopenProject(); await openNote('Retained source draft');
    await tapControl(screen.getByRole('button', { name: 'その他', exact: true }));
    await tapControl(screen.getByRole('button', { name: 'メモを編集', exact: true }));
    await expect(title).toHaveValue('Recovered source edit');
    await expect(body).toHaveValue('Edited body survives failed save');
    await tapControl(screen.getByRole('button', { name: '保存', exact: true }));
    await expect(screen.getByText('Edited body survives failed save', { exact: true })).toBeVisible();
    await app.restart(); await reopenProject(); await openNote('Recovered source edit');
    await expect(screen.getByText('Edited body survives failed save', { exact: true })).toBeVisible();
    await app.screenshot('source-edited-note-restored');
  } finally {
    try {
      if (database) for (const name of triggers) sql(database, `DROP TRIGGER IF EXISTS ${name};`);
    } finally { await device.setAppearance('light'); }
  }
});
