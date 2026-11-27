import { randomUUID } from 'node:crypto';
import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, restartToLibrary, scrollToControl, tapControl, tapTab } from './ui-helpers';
import { isolatedDatabase, sql } from './sqlite-fixture-helpers';

test('project source notes retain failed creates and edits, persist drafts, and recover after restart', { timeout: 360_000 }, async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  const marker = 'source-recovery-' + randomUUID();
  const project = 'SourceRecovery-' + randomUUID().slice(0, 8);
  const title = screen.getByRole('textbox', { name: 'タイトル', exact: true });
  const sourceAdd = screen.getByRole('button', { name: '参考資料を追加', exact: true }).first();
  const triggers = new Set<string>();
  let database: string | undefined;
  // A visible toolbar/row needs no drag. Pulling down at the top can dismiss
  // a native zoom destination rather than scroll its already visible content.
  const reveal = (control: any) => scrollToControl(screen, control);
  async function fillNote(name: string, text: string) {
    // The form lowers its keyboard as the next field is revealed; there is no
    // separate dismiss button any more.
    await reveal(title); await title.fill(name);
    const body = screen.getByRole('textbox', { name: 'ノート本文', exact: true });
    await reveal(body); await tapControl(screen, body); await expect(body).toBeFocused();
    await body.pressSequentially(text);
  }
  async function openNoteBody() {
    // A note's disclosure is labelled for its body, not the generic 原文.
    const body = screen.getByLabel('ノート本文').first();
    await reveal(body);
    await tapControl(body);
  }
  async function openNoteMenu() {
    // The source menu waits for the note's preparation (a local summary pass)
    // to finish, which can outlast the default assertion window.
    const more = screen.getByRole('button', { name: 'その他', exact: true });
    await expect(more).toBeEnabled({ timeout: 60_000 });
    await tapControl(more);
  }
  async function saveNote() {
    const save = screen.getByRole('button', { name: '保存', exact: true });
    await reveal(save); await tapControl(save);
  }
  async function openReferences() {
    // The workspace shows its five sections inline; there is no switcher menu.
    await tapControl(screen.getByRole('button', { name: '参考資料', exact: true }).last());
  }
  async function reopenProject() {
    // A restart can leave the driver bound to the closing scene.
    await restartToLibrary(app, screen);
    await tapControl(screen.getByRole('button', { name: 'プロジェクト', exact: true }));
    await tapControl(screen.getByText(project, { exact: true }).first());
    await openReferences();
  }
  async function openNote(name: string) {
    const row = screen.getByRole('button', { name: new RegExp('^' + name + '、メモ') }).last();
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
    await openReferences();
    await tapControl(sourceAdd);
    await fillNote(marker, 'Isolated source database identity');
    await saveNote();
    await expect(screen.getByRole('button', { name: new RegExp('^' + marker + '、メモ') }).first()).toBeVisible({ timeout: 60_000 });
    const identity = await device.foregroundApp();
    if (identity.bundleId !== 'app.bitrig.new.811eee03-bad9-4f5e-9d1d-d2820c1e93b4') throw new Error('Unexpected app');
    database = isolatedDatabase(marker, identity.bundleId, 'memoraProjectSources.v2');
    await tapControl(sourceAdd);
    await fillNote('Retained source draft', 'Body retained after actual SQLite failure');
    let recover = failSourceWrites();
    await saveNote();
    await expect(screen.getByText(/保存できませんでした/).first()).toBeVisible({ timeout: 60_000 });
    await reveal(title); await expect(title).toHaveValue('Retained source draft');
    await app.screenshot('source-create-failure-retains-draft');
    recover();
    // Closing/reopening and a process restart must retain both fields, not just body.
    await tapControl(screen.getByRole('button', { name: '閉じる', exact: true }));
    await reopenProject(); await tapControl(sourceAdd);
    await reveal(title); await expect(title).toHaveValue('Retained source draft');
    const restoredBody = screen.getByRole('textbox', { name: 'ノート本文', exact: true });
    await reveal(restoredBody); await expect(restoredBody).toHaveValue('Body retained after actual SQLite failure');
    await saveNote();
    await expect(screen.getByRole('button', { name: /^Retained source draft、メモ/ }).first()).toBeVisible({ timeout: 60_000 });
    await openNote('Retained source draft');
    await openNoteMenu();
    await tapControl(screen.getByRole('button', { name: 'メモを編集', exact: true }));
    const editTitle = screen.getByRole('textbox', { name: 'タイトル', exact: true });
    const editBody = screen.getByRole('textbox', { name: 'メモ本文', exact: true });
    await editTitle.fill('Recovered source edit');
    await editBody.fill('Edited body survives failed save');
    await device.setAppearance('dark');
    recover = failSourceWrites();
    await tapControl(screen.getByRole('button', { name: '保存', exact: true }));
    await expect(screen.getByText('保存できませんでした。開き直して確認してください。', { exact: true })).toBeVisible();
    await expect(editTitle).toHaveValue('Recovered source edit');
    await expect(editBody).toHaveValue('Edited body survives failed save');
    await app.screenshot('source-edit-failure-retains-draft');
    recover();
    await tapControl(screen.getByRole('button', { name: 'キャンセル', exact: true }));
    await reopenProject(); await openNote('Retained source draft');
    await openNoteMenu();
    await tapControl(screen.getByRole('button', { name: 'メモを編集', exact: true }));
    await expect(editTitle).toHaveValue('Recovered source edit');
    await expect(editBody).toHaveValue('Edited body survives failed save');
    await tapControl(screen.getByRole('button', { name: '保存', exact: true }));
    await openNoteBody();
    await expect(screen.getByText('Edited body survives failed save', { exact: true })).toBeVisible();
    await reopenProject(); await openNote('Recovered source edit');
    await openNoteBody();
    await expect(screen.getByText('Edited body survives failed save', { exact: true })).toBeVisible();
    await app.screenshot('source-edited-note-restored');
  } finally {
    try {
      if (database) for (const name of triggers) sql(database, `DROP TRIGGER IF EXISTS ${name};`);
    } finally { await device.setAppearance('light'); }
  }
});
