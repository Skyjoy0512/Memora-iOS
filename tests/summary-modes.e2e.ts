import { afterEach, test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { seedSummaryFixture } from './summary-fixture-helpers';
import { scrollToControl, tapControl, tapTab } from './ui-helpers';
import { sql } from './sqlite-fixture-helpers';

afterEach(async ({ device }) => { await device.setAppearance('light'); });

// Configure the supported provider explicitly, without a key or generation.
// This dedicated simulator starts with fresh data; its default is on-device.
test('summary processing mode is separate from detail and never regenerates on selection', { timeout: 240_000 }, async ({ app, device, screen }) => {
  const { database, summary, raw, title } = await seedSummaryFixture(app, device, screen);
  await tapControl(screen.getByTestId('BackButton'));
  await tapControl(screen.getByLabel('メニュー').first());
  await tapControl(screen.getByTestId('sidebar.settings'));
  const ai = screen.getByTestId('settings.category.ai').first();
  await scrollToControl(screen, ai);
  await tapControl(ai);
  await tapControl(screen.getByRole('button', { name: /^AIモデル/ }).first());
  await tapControl(screen.getByTestId('settings.ai.engine'));
  await tapControl(screen.getByRole('button', { name: 'クラウドAI', exact: true }));
  const service = screen.getByRole('button', { name: /^サービス/ }).first();
  await scrollToControl(screen, service);
  await tapControl(service);
  await tapControl(screen.getByRole('button', { name: /^DeepSeek/ }).first());
  await device.back();
  await device.back();
  await tapControl(screen.getByRole('button', { name: '閉じる', exact: true }));
  await tapTab(screen, 'ライブラリ');
  await tapControl(screen.getByRole('button', { name: new RegExp('^' + title) }).first());
  await tapControl(screen.getByRole('button', { name: 'その他', exact: true }));
  await tapControl(screen.getByTestId('meeting.summary.regenerate'));
  await tapControl(screen.getByTestId('summary.advanced'));
  const mode = screen.getByRole('button', { name: /^処理方法、/ });
  await scrollToControl(screen, mode);
  await expect(mode).toHaveAccessibleName(/標準/);
  const detail = screen.getByRole('tab', { name: '標準', exact: true });
  await expect(detail).toBeSelected();
  for (const choice of ['速く', 'じっくり', '標準']) {
    await tapControl(mode);
    await tapControl(screen.getByRole('button', { name: choice, exact: true }));
    await expect(mode).toHaveAccessibleName(new RegExp(choice));
    await expect(detail).toBeSelected();
    const records = JSON.parse(sql(database, "SELECT CAST(data AS TEXT) FROM documents WHERE key='memoraMeetings';"));
    expect(records[0].summary).toBe(summary);
    expect(records[0].transcript[0].text).toBe(raw);
  }
  await app.screenshot('summary-mode-standard-light');
  const engine = screen.getByTestId('summary.engineChoice');
  await scrollToControl(screen, engine);
  const engineBounds = await engine.boundingBox();
  const templateBounds = await screen.getByTestId('summary.templateChoice').boundingBox();
  expect(engineBounds).not.toBeNull();
  expect(templateBounds).not.toBeNull();
  expect(templateBounds!.y).toBeGreaterThanOrEqual(engineBounds!.y + engineBounds!.height);
  await expect(screen.getByTestId('summary.destination')).toHaveText(/DeepSeek · api.deepseek.com/);
  await device.setAppearance('dark');
  await app.screenshot('summary-mode-standard-dark');
  await tapControl(screen.getByRole('button', { name: 'キャンセル', exact: true }));
  const pending = sql(database, "SELECT CAST(data AS TEXT) FROM documents WHERE key='memoraPendingSummaryJobs';");
  expect(pending === '' || JSON.parse(pending).length === 0).toBe(true);
});
