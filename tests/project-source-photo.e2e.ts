import { createHash, randomUUID } from 'node:crypto';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, tapControl, tapTab } from './ui-helpers';
import { isolatedDatabase, sql } from './sqlite-fixture-helpers';

// Uses a stock photo in the dedicated simulator's library through the real
// PhotosPicker transfer. Never grants full-library access or uses user photos.
test('selected photo survives SQL failure, same-photo retry, deduplication and restart', { timeout: 360_000 }, async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  const marker = 'photo-retry-' + randomUUID();
  const project = 'Photo-' + randomUUID().slice(0, 8);
  const sourceAdd = screen.getByRole('button', { name: '参考資料を追加', exact: true }).first();
  const title = screen.getByRole('textbox', { name: 'タイトル', exact: true });
  const trigger = 'memora_photo_' + randomUUID().replaceAll('-', '');
  let database: string | undefined;
  let triggerInstalled = false;
  let stockPhotoName: string | undefined;
  async function openReferences() {
      await tapControl(screen.getByRole('button', { name: '参考資料', exact: true }).last());
  }
  async function dismissKeyboard() {
    for (const label of ['キーボードを閉じる', '完了']) {
      const control = screen.getByRole('button', { name: label, exact: true }).first();
      if (await control.isVisible()) { await tapControl(control); break; }
    }
    await expect(screen.getByRole('keyboard')).not.toBeVisible();
  }
  async function pickSamePhoto() {
    await tapControl(screen.getByLabel('資料を追加').first());
    await tapControl(screen.getByRole('button', { name: '写真を追加', exact: true }));
    await expect(screen.getByRole('tab', { name: '写真', exact: true })).toBeVisible();
    if (!stockPhotoName) {
      const stock = screen.getByRole('image', { name: /^写真, / }).first();
      await expect(stock).toBeVisible();
      stockPhotoName = await stock.textContent();
      if (!stockPhotoName) throw new Error('Stock simulator photo has no accessible label');
    }
    await tapControl(screen.getByRole('image', { name: stockPhotoName, exact: true }));
    const done = screen.getByRole('button', { name: '完了', exact: true });
    await expect(done).toBeEnabled();
    await tapControl(done);
  }
  try {
    await tapControl(screen.getByRole('button', { name: 'プロジェクト', exact: true }));
    await tapControl(screen.getByRole('button', { name: 'プロジェクトを作成', exact: true }).first());
    await screen.getByPlaceholder('例：新規アプリ').fill(project);
    await tapControl(screen.getByRole('button', { name: '作成', exact: true }));
    await openReferences();
    await tapControl(sourceAdd);
    await title.fill(marker);
    const body = screen.getByRole('textbox', { name: 'ノート本文', exact: true });
    await tapControl(screen, body);
    await expect(body).toBeFocused();
    await body.pressSequentially('baseline source');
    const closeKeyboard = screen.getByRole('button', { name: 'キーボードを閉じる', exact: true });
    if (await closeKeyboard.isVisible()) await tapControl(closeKeyboard);
    await expect(screen.getByRole('keyboard')).not.toBeVisible();
    await tapControl(screen.getByRole('button', { name: '保存', exact: true }));
    await expect(screen.getByRole('button', { name: new RegExp('^' + marker + '、メモ') }).first()).toBeVisible({ timeout: 60_000 });
    const identity = await device.foregroundApp();
    if (identity.bundleId !== 'app.bitrig.new.811eee03-bad9-4f5e-9d1d-d2820c1e93b4') throw new Error('Unexpected app');
    database = isolatedDatabase(marker, identity.bundleId, 'memoraProjectSources.v2');
    const read = () => JSON.parse(sql(database!, "SELECT CAST(data AS TEXT) FROM documents WHERE key='memoraProjectSources.v2';"));
    const before = read();
    const folder = join(dirname(database), 'WorkspaceFiles');
    const files = () => existsSync(folder) ? readdirSync(folder).sort() : [];
    const initialFiles = files();
    // Reopen on a settled project screen so the toolbar and sheet are not
    // tapped during the first save's dismissal animation.
    await app.restart();
    await tapTab(screen, 'ライブラリ');
    await tapControl(screen.getByRole('button', { name: 'プロジェクト', exact: true }));
    await tapControl(screen.getByText(project, { exact: true }).first());
    await openReferences();
    sql(database, `CREATE TRIGGER ${trigger} BEFORE INSERT ON documents WHEN NEW.key='memoraProjectSources.v2' BEGIN SELECT RAISE(ABORT, 'isolated photo failure'); END;`);
    triggerInstalled = true;
    await tapControl(sourceAdd);
    await expect(title).toBeVisible({ timeout: 10_000 });
    await title.fill('Photo draft');
    const draftBody = screen.getByRole('textbox', { name: 'ノート本文', exact: true });
    await expect(draftBody).toBeVisible({ timeout: 10_000 });
    await tapControl(screen, draftBody);
    await expect(draftBody).toBeFocused();
    await draftBody.pressSequentially('Draft retained after a photo save failure');
    if (await closeKeyboard.isVisible()) await tapControl(closeKeyboard);
    await expect(screen.getByRole('keyboard')).not.toBeVisible();
    await pickSamePhoto();
    await dismissKeyboard();
    await expect(screen.getByText(/保存できませんでした/).first()).toBeVisible({ timeout: 60_000 });
    await expect(title).toHaveValue('Photo draft');
    await expect(draftBody).toHaveValue('Draft retained after a photo save failure');
    expect(read().filter((source: any) => source.kind === 'image')).toEqual([]);
    expect(files()).toEqual(initialFiles);
    await app.screenshot('photo-save-failure-retains-input');
    sql(database, `DROP TRIGGER ${trigger};`); triggerInstalled = false;
    await pickSamePhoto();
    await expect(screen.getByRole('button', { name: /^写真、画像/ }).first()).toBeVisible({ timeout: 90_000 });
    await expect(title).toHaveValue('Photo draft');
    const imported = read().filter((source: any) => source.kind === 'image');
    expect(imported).toHaveLength(1);
    const photo = imported[0];
    expect(photo.projectID).toBe(before[0].projectID);
    expect(photo.localFileReference).toMatch(/^[0-9a-f-]{36}\.[a-z0-9]{1,12}$/i);
    for (const permission of ['allowsCloudAI', 'allowsAutomaticAgentAccess', 'allowsAutomaticWebhook', 'allowsTeamSharing']) {
      expect(photo.privacy[permission]).toBe(false);
    }
    expect(['ready', 'unavailable']).toContain(photo.processingStatus);
    expect(photo.errorInformation).toBe('画像は先頭フレームのOCRで読み取った文字を参照します。画像内容のAI解析は行っていません。');
    const original = readFileSync(join(folder, photo.localFileReference));
    expect(original.length).toBeGreaterThan(0);
    expect(createHash('sha256').update(original).digest('hex')).toBe(photo.contentFingerprint);
    const saved = read();
    const retainedFiles = files();
    // A fresh form has no previous success label that could satisfy the next
    // assertion before the third transfer has actually completed.
    await tapControl(screen.getByRole('button', { name: '閉じる', exact: true }));
    await tapControl(sourceAdd);
    await pickSamePhoto();
    await expect(screen.getByRole('button', { name: /^写真、画像/ }).first()).toBeVisible({ timeout: 60_000 });
    expect(read()).toEqual(saved);
    expect(files()).toEqual(retainedFiles);
    expect(readFileSync(join(folder, photo.localFileReference))).toEqual(original);
    await tapControl(screen.getByRole('button', { name: '閉じる', exact: true }));
    await tapControl(screen.getByRole('button', { name: /^写真、/ }).first());
    await expect(screen.getByText(photo.errorInformation, { exact: true })).toBeVisible();
    await expect(screen.getByRole('button', { name: '元のファイルを開く', exact: true })).toBeVisible();
    await app.screenshot('photo-import-ocr-scope');
    await app.restart();
    await tapTab(screen, 'ライブラリ');
    await tapControl(screen.getByRole('button', { name: 'プロジェクト', exact: true }));
    await tapControl(screen.getByText(project, { exact: true }).first());
    await openReferences();
    await tapControl(screen.getByRole('button', { name: /^写真、/ }).first());
    await expect(screen.getByText(photo.errorInformation, { exact: true })).toBeVisible();
    expect(read()).toEqual(saved);
    expect(files()).toEqual(retainedFiles);
    expect(readFileSync(join(folder, photo.localFileReference))).toEqual(original);
    await app.screenshot('photo-import-restored');
  } finally {
    if (database && triggerInstalled) sql(database, `DROP TRIGGER IF EXISTS ${trigger};`);
  }
});
