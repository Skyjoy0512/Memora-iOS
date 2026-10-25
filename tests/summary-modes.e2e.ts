import { afterEach, test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { seedSummaryFixture } from './summary-fixture-helpers';
import { scrollToControl, tapControl } from './ui-helpers';
import { sql } from './sqlite-fixture-helpers';

afterEach(async ({ device }) => { await device.setAppearance('light'); });

// No generation button, model calls or external services. The dedicated test
// simulator is identified by the fixture's UI-created UUID before SQLite reads.
test('summary processing mode is separate from detail and never regenerates on selection', { timeout: 180_000 }, async ({ app, device, screen }) => {
  const { database, summary, raw } = await seedSummaryFixture(app, device, screen);
  await tapControl(screen.getByRole('button', { name: 'その他', exact: true }));
  await tapControl(screen.getByRole('button', { name: '要約をやり直す', exact: true }));
  const mode = screen.getByTestId('summary.processingMode');
  await scrollToControl(screen, mode);
  await expect(mode).toHaveAccessibleName(/標準/);
  const detail = screen.getByRole('tab', { name: '標準', exact: true });
  await expect(detail).toBeSelected();
  for (const choice of ['高速', '高精度', '標準']) {
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
  const explanationBounds = await screen.getByTestId('summary.engineApproach').boundingBox();
  expect(engineBounds).not.toBeNull();
  expect(explanationBounds).not.toBeNull();
  expect(explanationBounds!.y).toBeGreaterThanOrEqual(engineBounds!.y + engineBounds!.height);
  await device.setAppearance('dark');
  await app.screenshot('summary-mode-standard-dark');
  await tapControl(screen.getByRole('button', { name: 'キャンセル', exact: true }));
  const pending = sql(database, "SELECT CAST(data AS TEXT) FROM documents WHERE key='memoraPendingSummaryJobs';");
  expect(pending === '' || JSON.parse(pending).length === 0).toBe(true);
});
