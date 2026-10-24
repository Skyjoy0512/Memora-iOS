import { randomUUID } from 'node:crypto';
import { expect } from 'e2e';
import { launchMemora, tapControl, tapTab } from './ui-helpers';
import { isolatedDatabase, sql } from './sqlite-fixture-helpers';

// A positive UI-created UUID marker identifies only this fresh test simulator.
// Never seed the preview, a real device or a database with existing meetings.
export async function seedSummaryFixture(app: any, device: any, screen: any,
  content?: { summary: string; raw: string; segmentID: string; timestamp: number }) {
  await launchMemora(app, device, screen);
  const marker = 'summary-reading-' + randomUUID();
  await device.openLink('memora://new-memo');
  await screen.getByRole('textbox', { name: 'メモのタイトル', exact: true }).fill(marker);
  await tapControl(screen.getByRole('button', { name: '追加', exact: true }));
  await expect(screen.getByText('ライフログを追加', { exact: true })).not.toBeVisible();
  const identity = await device.foregroundApp();
  if (identity.bundleId !== 'app.bitrig.new.811eee03-bad9-4f5e-9d1d-d2820c1e93b4') throw new Error('Unexpected app');
  const database = isolatedDatabase(marker, identity.bundleId);
  const existing = sql(database, "SELECT CAST(data AS TEXT) FROM documents WHERE key='memoraMeetings';");
  expect(existing === '' || JSON.parse(existing).length === 0).toBe(true);
  const title = '検証用・発売準備ミーティング';
  const summary = content?.summary ?? '## 会議の概要\n予算は10万円ではなく12万円。承認された場合だけ来週実施する。\n\n## 決定事項\n- 本番切替はしない\n- 検証環境で比較する\n\n## アクションアイテム\n| タイトル | 詳細 | 担当 | 期限 |\n| --- | --- | --- | --- |\n| 予算案を確認 | 承認が前提 | 佐藤 | 来週 |\n| 結果を共有 | 否決時は延期 | 未定 | 未記載 |\n\n## 未解決事項\n- 承認日は未確定';
  const raw = content?.raw ?? 'えーと、えっと、予算は10万円ではなく12万円です。';
  const timestamp = Date.parse('2026-10-24T01:00:00Z') / 1000 - 978307200;
  const fixture = { id: randomUUID(), title, createdAt: timestamp, duration: 120, source: 'importFile', status: { ready: {} },
    summary, keyPoints: [], decisions: [], openQuestions: [],
    transcript: [{ id: content?.segmentID ?? randomUUID(), speaker: '話者1', speakerIsCertain: true, timestamp: content?.timestamp ?? 0, text: raw }] };
  await device.closeApp();
  const bytes = Buffer.from(JSON.stringify([fixture]), 'utf8').toString('hex');
  sql(database, `INSERT OR REPLACE INTO documents (key,data,updated_at) VALUES ('memoraMeetings',X'${bytes}',${timestamp});`);
  await app.restart();
  await tapTab(screen, 'ライブラリ');
  await tapControl(screen.getByRole('button', { name: new RegExp('^' + title) }).first());
  return { database, identity, fixture, title, summary, raw, marker };
}
