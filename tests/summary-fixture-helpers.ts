import { randomUUID } from 'node:crypto';
import { expect } from 'e2e';
import { launchMemora, requireRootMenu, tapControl, tapTab } from './ui-helpers';
import { isolatedDatabase, readMeetings, sql, writeMeetings } from './sqlite-fixture-helpers';

// A positive UI-created UUID marker identifies only this fresh test simulator.
// Never seed the preview, a real device or a database with existing meetings.
export async function seedSummaryFixture(app: any, device: any, screen: any,
  content?: { summary: string; raw: string; segmentID: string; timestamp: number }) {
  await launchMemora(app, device, screen);
  const marker = 'summary-reading-' + randomUUID();
  await device.openLink('memora://new-memo');
  const titleField = screen.getByRole('textbox', { name: 'タイトル', exact: true });
  const confirmOpen = screen.getByRole('button', { name: '開く', exact: true });
  await expect.poll(async () => await titleField.isVisible() || await confirmOpen.isVisible()).toBe(true);
  if (await confirmOpen.isVisible()) await tapControl(confirmOpen);
  await screen.getByRole('textbox', { name: 'タイトル', exact: true }).fill(marker);
  const body = screen.getByRole('textbox', { name: 'ノート本文', exact: true });
  await tapControl(body);
  // UITextView can have a visible insertion caret without exposing AX focus.
  // Verify actual entry rather than that unreliable accessibility flag.
  // Start at the top of the empty field; its centre can be below the keyboard.
  const markerBody = 'Isolated summary fixture ' + marker;
  await body.tap({ position: { x: 12, y: 12 } });
  await body.pressSequentially(markerBody, { timeout: 30_000 });
  await expect(body).toHaveValue(markerBody);
  const closeKeyboard = screen.getByRole('button', { name: 'キーボードを閉じる', exact: true });
  if (await closeKeyboard.isVisible()) await tapControl(closeKeyboard);
  await tapControl(screen.getByRole('button', { name: '保存', exact: true }));
  await expect(body).not.toBeVisible();
  const identity = await device.foregroundApp();
  if (identity.bundleId !== 'app.bitrig.new.811eee03-bad9-4f5e-9d1d-d2820c1e93b4') throw new Error('Unexpected app');
  const database = isolatedDatabase(marker, identity.bundleId, 'memoraProjectSources.v2');
  const existing = readMeetings(database) ?? [];
  expect(existing.length).toBe(0);
  const title = '検証用・発売準備ミーティング';
  const summary = content?.summary ?? '## 会議の概要\n予算は10万円ではなく12万円。承認された場合だけ来週実施する。\n\n## 決定事項\n- 本番切替はしない\n- 検証環境で比較する\n\n## アクションアイテム\n| タイトル | 詳細 | 担当 | 期限 |\n| --- | --- | --- | --- |\n| 予算案を確認 | 承認が前提 | 佐藤 | 来週 |\n| 結果を共有 | 否決時は延期 | 未定 | 未記載 |\n\n## 未解決事項\n- 承認日は未確定';
  const raw = content?.raw ?? 'えーと、えっと、予算は10万円ではなく12万円です。';
  const timestamp = Date.parse('2026-10-24T01:00:00Z') / 1000 - 978307200;
  const fixture = { id: randomUUID(), title, createdAt: timestamp, duration: 120, source: 'importFile', status: { ready: {} },
    summary, keyPoints: [], decisions: [], openQuestions: [],
    transcript: [{ id: content?.segmentID ?? randomUUID(), speaker: '話者1', speakerIsCertain: true, timestamp: content?.timestamp ?? 0, text: raw }] };
  await device.closeApp();
  writeMeetings(database, [fixture]);
  await app.restart();
  await requireRootMenu(app, screen);
  await tapTab(screen, 'ライブラリ');
  await tapControl(screen.getByRole('button', { name: new RegExp('^' + title) }).first());
  return { database, identity, fixture, title, summary, raw, marker };
}
