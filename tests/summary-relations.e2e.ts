import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { seedSummaryFixture } from './summary-fixture-helpers';
import { sql } from './sqlite-fixture-helpers';
import { tapControl, tapTab, scrollToControl, openSummaryPoster } from './ui-helpers';

afterEach(async ({ device }) => { await device.setAppearance('light'); });

// The fixture comes from the actual validator + SummaryMarkdownBuilder host
// check, not an AI run. The model/session and real audio are not exercised.
test('validated on-device summary relations survive reading, editing and restart', { timeout: 240_000, skip: 'The one-page summary poster is compiled off (FeatureFlags.isInlineSummaryPosterEnabled is false).' }, async ({ app, device, screen }) => {
  const supplied = process.env.MEMORA_SUMMARY_RELATION_FIXTURE;
  const temporary = supplied ? undefined : mkdtempSync(join(process.env.MEMORA_CHECK_ROOT ?? tmpdir(), 'memora-relation-e2e-'));
  const path = supplied ?? join(temporary!, 'fixture.json');
  try {
    if (temporary) execFileSync('bash', ['tools/checks/run-summary-reading-checks.sh', '--fixture', path], { timeout: 120_000 });
    const generated = JSON.parse(readFileSync(path, 'utf8'));
    expect(generated.kind).toBe('production-builder-fixture');
    for (const name of ['summary', 'raw', 'parent', 'child', 'segmentID']) {
      if (typeof generated[name] !== 'string' || !generated[name]) throw new Error('Invalid relation fixture: ' + name);
    }
    const { database, title, fixture } = await seedSummaryFixture(app, device, screen, { ...generated, timestamp: 12 });
    const read = () => JSON.parse(sql(database, "SELECT CAST(data AS TEXT) FROM documents WHERE key='memoraMeetings';"));
    await expect(screen.getByTestId('summary.poster.inline')).toBeVisible();
    await openSummaryPoster(screen);
    await expect(screen.getByTestId('summary.poster.image')).toBeVisible();
    await tapControl(screen.getByRole('tab', { name: '全文', exact: true }));
    const child = screen.getByText(generated.child, { exact: true });
    await scrollToControl(screen, child);
    await expect(child).toBeVisible();
    await app.screenshot('validated-relations-full-text-light');
    await device.setAppearance('dark');
    await app.screenshot('validated-relations-full-text-dark');
    await tapControl(screen.getByRole('button', { name: '完了', exact: true }));
    const editable = screen.getByRole('button', { name: generated.child, exact: true });
    await scrollToControl(screen, editable);
    await tapControl(editable);
    const edited = '理由：検証結果はまだ未確認です（表示編集の検証）。';
    const field = screen.getByRole('textbox', { name: '本文', exact: true });
    await expect(field).toHaveValue(generated.child);
    await expect(field).toBeFocused();
    await field.fill(edited);
    await tapControl(screen.getByRole('button', { name: '完了', exact: true }));
    await expect.poll(() => read()[0].summary.includes('  - ' + edited)).toBe(true);
    expect(read()[0].summary).toContain(generated.parent);
    expect(read()[0].transcript[0].text).toBe(generated.raw);
    expect(read()[0].id.toLowerCase()).toBe(fixture.id.toLowerCase());
    await app.restart();
    await tapTab(screen, 'ライブラリ');
    await tapControl(screen.getByRole('button', { name: new RegExp('^' + title) }).first());
    await expect(screen.getByTestId('summary.poster.inline')).toBeVisible();
    await scrollToControl(screen, screen.getByRole('button', { name: edited, exact: true }));
    await expect(screen.getByRole('button', { name: edited, exact: true })).toBeVisible();
    expect(read()[0].summary).toContain('  - ' + edited);
    expect(read()[0].transcript[0].id.toLowerCase()).toBe(generated.segmentID.toLowerCase());
    await app.screenshot('validated-relations-edited-restored');
  } finally {
    if (temporary) rmSync(temporary, { recursive: true, force: true });
  }
});
