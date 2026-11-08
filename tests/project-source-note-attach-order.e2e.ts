import { randomUUID } from 'node:crypto';
import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, selectLibrarySection, tapControl, tapTab } from './ui-helpers';
import { isolatedDatabase, sql } from './sqlite-fixture-helpers';

// The attach sheet must save sources in the order they were tapped, survive a
// restart, and keep reorder/detach behaviour. All data stays in the isolated
// simulator store.
test('a note saves attached sources in tap order and keeps it after restart', { timeout: 300_000 }, async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  const project = 'Attach-' + randomUUID().slice(0, 8);
  const marker = 'AttachOrder-' + randomUUID().slice(0, 8);
  const titles = [marker + '-A', marker + '-B', marker + '-C'];
  const sourceAdd = screen.getByRole('button', { name: '参考資料を追加', exact: true }).first();
  const titleField = screen.getByRole('textbox', { name: 'タイトル', exact: true });
  const closeKeyboard = screen.getByRole('button', { name: 'キーボードを閉じる', exact: true });

  async function openReferences() {
    await tapControl(screen.getByRole('pop-up-button', { name: /表示切り替え$/ }));
    await tapControl(screen.getByRole('button', { name: '参考資料', exact: true }).last());
  }

  async function addNote(title: string, body: string) {
    await tapControl(sourceAdd);
    await titleField.fill(title);
    const bodyField = screen.getByRole('textbox', { name: 'ノート本文', exact: true });
    await tapControl(screen, bodyField);
    await bodyField.pressSequentially(body);
    if (await closeKeyboard.isVisible()) await tapControl(closeKeyboard);
    await expect(screen.getByRole('keyboard')).not.toBeVisible();
    await tapControl(screen.getByRole('button', { name: '保存', exact: true }));
    await expect(screen.getByRole('button', { name: new RegExp('^' + title + '、メモ') }).first())
      .toBeVisible({ timeout: 60_000 });
  }

  function sources(database: string): any[] {
    return JSON.parse(sql(database, "SELECT CAST(data AS TEXT) FROM documents WHERE key='memoraProjectSources.v2';"));
  }

  await selectLibrarySection(screen, 'プロジェクト');
  await tapControl(screen.getByRole('button', { name: 'プロジェクトを作成', exact: true }).first());
  await screen.getByPlaceholder('例：新規アプリ').fill(project);
  await tapControl(screen.getByRole('button', { name: '作成', exact: true }));
  await openReferences();
  for (const [index, title] of titles.entries()) {
    await addNote(title, `本文 ${index} ${marker}`);
  }

  const identity = await device.foregroundApp();
  const database = isolatedDatabase(marker, identity.bundleId, 'memoraProjectSources.v2');
  const byTitle = () => new Map(sources(database).map((source: any) => [source.title, source]));
  const idFor = (title: string) => {
    const source = byTitle().get(title);
    if (!source) throw new Error(`source missing: ${title}`);
    return source.id as string;
  };
  const attached = (title: string) => (byTitle().get(title)?.attachedSourceIDs ?? []) as string[];

  // Attach B, then C, so the chosen order is B, C rather than any set order.
  await tapControl(screen.getByRole('button', { name: new RegExp('^' + titles[0] + '、メモ') }).first());
  await tapControl(screen.getByRole('button', { name: 'その他', exact: true }));
  await tapControl(screen.getByRole('button', { name: '資料を添付', exact: true }));
  await tapControl(screen.getByRole('button', { name: new RegExp('^' + titles[1] + '、メモ') }).first());
  await tapControl(screen.getByRole('button', { name: new RegExp('^' + titles[2] + '、メモ') }).first());
  await tapControl(screen.getByRole('button', { name: '添付', exact: true }));
  await expect.poll(() => attached(titles[0]).length).toBe(2);
  expect(attached(titles[0])).toEqual([idFor(titles[1]), idFor(titles[2])]);
  await app.screenshot('note-attachments-in-tap-order');

  // Order and links survive a relaunch from SQLite.
  await app.restart();
  await tapTab(screen, 'ライブラリ');
  await selectLibrarySection(screen, 'プロジェクト');
  await tapControl(screen.getByText(project, { exact: true }).first());
  await openReferences();
  await tapControl(screen.getByRole('button', { name: new RegExp('^' + titles[0] + '、メモ') }).first());
  await expect(screen.getByText(titles[1], { exact: true }).first()).toBeVisible({ timeout: 30_000 });
  await expect(screen.getByText(titles[2], { exact: true }).first()).toBeVisible({ timeout: 30_000 });
  expect(attached(titles[0])).toEqual([idFor(titles[1]), idFor(titles[2])]);

  // Detach the last attachment from the note's own menu.
  await tapControl(screen.getByLabel('添付の操作').last());
  await tapControl(screen.getByRole('button', { name: '添付を解除', exact: true }));
  await expect.poll(() => attached(titles[0]).length).toBe(1);
  expect(attached(titles[0])).toEqual([idFor(titles[1])]);
  await app.screenshot('note-attachments-after-detach');
});
