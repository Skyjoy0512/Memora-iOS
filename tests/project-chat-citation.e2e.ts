import { randomUUID } from 'node:crypto';
import { copyFileSync, mkdirSync, statSync, unlinkSync, utimesSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { seedSummaryFixture } from './summary-fixture-helpers';
import { sql } from './sqlite-fixture-helpers';
import { requireRootMenu, selectLibrarySection, tapControl, tapTab } from './ui-helpers';

test('project chat cites dates and original photos and revalidates their availability', { timeout: 180_000 }, async ({ app, device, screen }) => {
  const { database, fixture } = await seedSummaryFixture(app, device, screen);
  await device.closeApp();
  const originalProject = { id: randomUUID(), name: '公開準備プロジェクト', symbol: 'folder' };
  const otherProject = { id: randomUUID(), name: '移動先プロジェクト', symbol: 'folder' };
  const photoName = fixture.id + '.jpg';
  const retained = { ...fixture, spaceID: originalProject.id, photoFileNames: [photoName] };
  const moved = { ...retained, id: randomUUID(), title: '移動済みの根拠', spaceID: otherProject.id, photoFileNames: [] };
  const photosPath = resolve(dirname(database), '../../..', 'Documents', 'Photos');
  mkdirSync(photosPath, { recursive: true });
  const originalPhoto = join(photosPath, photoName);
  copyFileSync(join(import.meta.dirname, 'fixtures', 'photo-ocr-quartz.jpg'), originalPhoto);
  const unixDate = fixture.createdAt + 978307200;
  utimesSync(originalPhoto, unixDate, unixDate);
  const byteCount = statSync(originalPhoto).size;
  const recognizedText = 'QUARTZ LEDGER';
  const mediaIndex = {
    name: photoName, recordID: retained.id, recordTitle: retained.title,
    recordDate: fixture.createdAt, byteCount, fileModifiedAt: fixture.createdAt,
    pixelWidth: 0, pixelHeight: 0, text: recognizedText, textReadAt: fixture.createdAt,
  };
  const citation = (record: typeof retained) => ({
    id: randomUUID(), target: { meeting: { _0: record.id } }, title: record.title,
    excerpt: record.transcript[0].text, recordedAt: record.createdAt,
  });
  const photoReference = {
    ...citation(retained), excerpt: recognizedText,
    photo: { name: photoName, byteCount, modifiedAt: fixture.createdAt, textReadAt: fixture.createdAt },
  };
  const thread = {
    id: randomUUID(), projectID: originalProject.id, title: '以前の回答',
    createdAt: fixture.createdAt, updatedAt: fixture.createdAt,
    messages: [{
      id: randomUUID(), role: 'assistant', text: '保存された出典を参照できます。',
      createdAt: fixture.createdAt, citations: [citation(moved), citation(retained), photoReference],
    }],
  };
  const values = [
    ['memoraSpaces', [originalProject, otherProject]],
    ['memoraMeetings', [retained, moved]],
    ['memoraProjectChats.v2', [thread]],
    ['memora.mediaIndex.v1', [mediaIndex]],
    ['memoraAIHistory', [{
      id: randomUUID(), question: '写真の内容を確認する', answer: '写真には QUARTZ LEDGER とあります。【写真1】',
      scopeLabel: retained.title, createdAt: fixture.createdAt, sourceCitations: [photoReference],
    }]],
  ].map(([key, data]) => "('" + key + "',X'" + Buffer.from(JSON.stringify(data)).toString('hex') + "'," + fixture.createdAt + ')');
  sql(database, 'INSERT OR REPLACE INTO documents (key,data,updated_at) VALUES ' + values.join(','));

  await app.restart();
  await requireRootMenu(app, screen);
  await selectLibrarySection(screen, 'プロジェクト');
  await tapControl(screen.getByRole('button', { name: new RegExp('^' + originalProject.name) }).first());
  await tapControl(screen.getByRole('button', { name: 'チャット', exact: true }));
  await tapControl(screen.getByRole('button', { name: /^以前の回答/ }));
  await tapControl(screen.getByText('出典', { exact: true }));

  const movedCitation = screen.getByRole('button', { name: /移動済みの根拠.*記録日/ });
  const retainedCitation = screen.getByRole('button', { name: /検証用・発売準備ミーティング.*記録日 \S+$/ });
  const photoCitation = screen.getByRole('button', { name: /検証用・発売準備ミーティング.*写真の文字/ });
  await expect(movedCitation).toBeVisible();
  await expect(retainedCitation).toBeVisible();
  await app.screenshot('project-chat-dated-citations');
  await tapControl(movedCitation);
  await expect(screen.getByText('元のソースが見つかりません', { exact: true })).toBeVisible();
  await tapControl(screen.getByRole('button', { name: '閉じる', exact: true }).last());
  await tapControl(photoCitation);
  await expect(screen.getByLabel(retained.title + 'の写真', { exact: true })).toBeVisible();
  await app.screenshot('project-chat-original-photo');
  await tapControl(screen.getByRole('button', { name: '閉じる', exact: true }).last());
  unlinkSync(originalPhoto);
  await tapControl(photoCitation);
  await expect(screen.getByText('元のソースが見つかりません', { exact: true })).toBeVisible();
  await tapControl(screen.getByRole('button', { name: '閉じる', exact: true }).last());
  await tapControl(retainedCitation);
  await expect(screen.getByText('文字起こし', { exact: true }).first()).toBeVisible();
  await expect(screen.getByText(retained.title, { exact: true })).toBeVisible();
  await expect(screen.getByRole('button', { name: '予算は10万円ではなく12万円です。', exact: true })).toBeVisible();

  // A previously saved record answer uses the same numbered picture citation
  // in its history. Recreate only this scenario's synthetic original.
  copyFileSync(join(import.meta.dirname, 'fixtures', 'photo-ocr-quartz.jpg'), originalPhoto);
  utimesSync(originalPhoto, unixDate, unixDate);
  await tapControl(screen.getByTestId('BackButton').first());
  await tapTab(screen, 'Ask AI');
  await tapControl(screen.getByRole('button', { name: '履歴', exact: true }));
  await tapControl(screen.getByText('写真の内容を確認する', { exact: true }).first());
  await tapControl(screen.getByText('出典', { exact: true }));
  const numberedPhoto = screen.getByRole('button', { name: '写真1 · ' + retained.title, exact: true });
  await tapControl(numberedPhoto);
  await expect(screen.getByLabel(retained.title + 'の写真', { exact: true })).toBeVisible();
  await app.screenshot('record-answer-numbered-original-photo');
  await tapControl(screen.getByRole('button', { name: '閉じる', exact: true }).last());
  unlinkSync(originalPhoto);
  await tapControl(numberedPhoto);
  await expect(screen.getByText('元の写真が見つかりません', { exact: true })).toBeVisible();
});
