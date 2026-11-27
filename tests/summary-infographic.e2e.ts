import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { seedSummaryFixture } from './summary-fixture-helpers';
import { sql } from './sqlite-fixture-helpers';
import { scrollToControl, tapControl, tapTab, openSummaryPoster, openSummaryImageMenu } from './ui-helpers';

test('separate infographic restores evidence and stages three record questions without sending', { timeout: 300_000, skip: 'The one-page summary poster is compiled off (FeatureFlags.isInlineSummaryPosterEnabled is false).' }, async ({ app, device, screen }) => {
  const { database, fixture, title, summary, raw } = await seedSummaryFixture(app, device, screen);
  const privacy = { classification: 'unknown', allowsCloudAI: false, allowsAutomaticAgentAccess: false,
    allowsAutomaticWebhook: false, allowsTeamSharing: false, updatedAt: fixture.createdAt };
  const questions = ['承認前に準備できることは？', '検証と本番の境界を整理して', '未確定事項を確認する順番は？'];
  // Explicit UI fixture, not a claim that a real model ran. The production
  // generator/validator/SQLite path is separately exercised by host checks.
  const document = { version: 1, meetingID: fixture.id, sourceSummary: summary, privacy,
    modelLabel: 'UI検証用・実モデル未実行', generatedAt: fixture.createdAt,
    content: {
      headline: { label: '判断軸', text: '本番切替はしない', evidence: '- 本番切替はしない\n- 検証環境で比較する' },
      panels: [
        { title: '予算と前提', kind: 'metric', items: [
          { label: '予算', text: '予算は10万円ではなく12万円。承認された場合だけ来週実施する。', evidence: '予算は10万円ではなく12万円。承認された場合だけ来週実施する。' },
          { label: '前提', text: '承認された場合だけ来週実施する。', evidence: '承認された場合だけ来週実施する。' }] },
        { title: '残る判断', kind: 'note', items: [
          { label: '未確定', text: '承認日は未確定', evidence: '承認日は未確定' }] },
      ], questions,
    } };
  const savedFixture = { ...fixture, privacy, summaryInfographicJSON: JSON.stringify(document) };
  await device.closeApp();
  const bytes = Buffer.from(JSON.stringify([savedFixture]), 'utf8').toString('hex');
  sql(database, `UPDATE documents SET data=X'${bytes}' WHERE key='memoraMeetings';`);
  await app.restart();
  await tapTab(screen, 'ライブラリ');
  await tapControl(screen.getByRole('button', { name: new RegExp('^' + title) }).first());
  await expect(screen.getByTestId('summary.poster.inline')).toHaveAccessibleName(/本番切替はしない/);
  await expect(screen.getByText('1枚サマリー', { exact: true })).not.toBeVisible();
  await expect(screen.getByText('拡大・共有', { exact: true })).not.toBeVisible();
  await expect(screen.getByRole('button', { name: 'AIで図解を再生成', exact: true })).not.toBeVisible();
  await openSummaryPoster(screen);
  await expect(screen.getByTestId('summary.poster.image')).toBeVisible();
  await app.screenshot('infographic-restored-image');
  await tapControl(screen.getByRole('tab', { name: '全文', exact: true }));
  await expect(screen.getByText('図解の読み方と根拠', { exact: true })).toBeVisible();
  await expect(screen.getByText('本番切替はしない', { exact: true })).toBeVisible();
  await app.screenshot('infographic-evidence');
  await tapControl(screen.getByRole('button', { name: '完了', exact: true }));
  const prepare = screen.getByRole('button', { name: 'AIで図解を再生成', exact: true });
  await openSummaryImageMenu(screen);
  await tapControl(prepare);
  await expect(screen.getByTestId('summary.infographic.generate')).toBeVisible();
  await expect(screen.getByText('内容を整理しています…', { exact: true })).not.toBeVisible();
  await tapControl(screen.getByRole('button', { name: 'キャンセル', exact: true }));
  expect(JSON.parse(sql(database, "SELECT CAST(data AS TEXT) FROM documents WHERE key='memoraMeetings';"))[0].summaryInfographicJSON).toBe(savedFixture.summaryInfographicJSON);
  const first = screen.getByTestId('summary.question.0');
  await scrollToControl(screen, first, { minimumY: 100, maximumY: 750 });
  await expect(screen.getByTestId(/^summary\.question\.\d$/)).toHaveCount(3);
  const box = await first.boundingBox();
  expect(box!.height).toBeGreaterThanOrEqual(44);
  await app.screenshot('infographic-three-record-questions');
  const conversationBefore = sql(database, "SELECT CAST(data AS TEXT) FROM documents WHERE key='memora.activeAIConversation.v1.personal';");
  await tapControl(first);
  const input = screen.getByTestId('ai.composer.input');
  await expect(input).toHaveValue(questions[0]);
  expect(sql(database, "SELECT CAST(data AS TEXT) FROM documents WHERE key='memora.activeAIConversation.v1.personal';")).toBe(conversationBefore);
  const second = screen.getByTestId('summary.question.1');
  await scrollToControl(screen, second);
  await expect(second).toBeDisabled();
  await expect(input).toHaveValue(questions[0]);
  await app.restart();
  await tapTab(screen, 'ライブラリ');
  await tapControl(screen.getByRole('button', { name: new RegExp('^' + title) }).first());
  await expect(screen.getByTestId('summary.poster.inline')).toHaveAccessibleName(/本番切替はしない/);
  const restored = JSON.parse(sql(database, "SELECT CAST(data AS TEXT) FROM documents WHERE key='memoraMeetings';"))[0];
  expect(restored.summaryInfographicJSON).toBe(savedFixture.summaryInfographicJSON);
  expect(restored.summary).toBe(summary);
  expect(restored.transcript[0].text).toBe(raw);
});
