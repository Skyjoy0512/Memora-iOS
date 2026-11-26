import { execFileSync } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { realpathSync } from 'node:fs';
import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { seedSummaryFixture } from './summary-fixture-helpers';
import { scrollToControl, tapControl, tapTab } from './ui-helpers';

test('transcript and purpose catalogs remain usable at largest Dynamic Type', { timeout: 240_000 }, async ({ app, device, screen }) => {
  const { database, identity } = await seedSummaryFixture(app, device, screen);
  const match = database.match(/\/CoreSimulator\/Devices\/([a-f0-9-]{36})\/data\/Containers\/Data\/Application\//i);
  if (!match) throw new Error('Cannot identify isolated simulator');
  const id = match[1];
  const container = execFileSync('xcrun', ['simctl', 'get_app_container', id, identity.bundleId!, 'data'], { encoding: 'utf8' }).trim();
  expect(realpathSync(container)).toBe(realpathSync(resolve(dirname(database), '../../..')));
  const size = (...args: string[]) => execFileSync('xcrun', ['simctl', 'ui', id, 'content_size', ...args], { encoding: 'utf8' }).trim();
  const previous = size();
  if (!/^(extra-small|small|medium|large|extra-large|extra-extra-large|extra-extra-extra-large|accessibility-medium|accessibility-large|accessibility-extra-large|accessibility-extra-extra-large|accessibility-extra-extra-extra-large)$/.test(previous)) throw new Error('Unknown text size');
  try {
    size('accessibility-extra-extra-extra-large');
    await tapControl(screen.getByRole('button', { name: /表示する項目/ }).first());
    await tapControl(screen.getByRole('button', { name: '文字起こし', exact: true }).last());
    const search = screen.getByTestId('transcript.search');
    const composerBeforeSearch = await screen.getByTestId('ai.composer.input').boundingBox();
    const editShortcut = await screen.getByTestId('record.aiEdit.open').boundingBox();
    const back = await screen.getByTestId('BackButton').first().boundingBox();
    if (!composerBeforeSearch || !back) throw new Error('Missing record navigation or composer frame');
    await scrollToControl(screen, search, {
      minimumY: back.y + back.height, maximumY: Math.min(composerBeforeSearch.y, editShortcut?.y ?? Infinity),
    });
    await expect(search).toBeVisible();
    await device.setAppearance('dark');
    await app.screenshot('transcript-largest-dark');
    await tapControl(screen, search);
    const transcriptQuery = screen.getByTestId('transcript.search.input');
    await expect(transcriptQuery).toBeFocused();
    await expect.poll(async () => {
      const field = await transcriptQuery.boundingBox();
      const composer = await screen.getByTestId('ai.composer.input').boundingBox();
      if (field && composer && field.y >= 120 && field.y + field.height <= composer.y) return 'clear';
      return JSON.stringify({ field, composer });
    }).toBe('clear');
    await transcriptQuery.fill('10万円');
    await scrollToControl(screen, screen.getByRole('button', { name: '予算は10万円ではなく12万円です。', exact: true }));
    await app.screenshot('transcript-largest-search');
    await tapControl(screen.getByTestId('BackButton'));
    await tapTab(screen, 'マーケットプレイス');
    await expect(screen.getByRole('button', { name: /表示する項目/ }).first()).toBeVisible();
    const query = screen.getByTestId('collection.search.input');
    await query.fill('復習クイズ');
    await tapControl(screen.getByTestId('Search'));
    await tapControl(screen.getByTestId('marketplace.catalog.skill:study-quiz').first());
    const use = screen.getByTestId('marketplace.detail.useSkill');
    await expect(use).toBeVisible();
    const box = await use.boundingBox();
    if (!box) throw new Error('Missing primary action');
    expect(box.height).toBeGreaterThanOrEqual(44);
    await app.screenshot('learning-skill-largest-dark');
    await tapControl(use);
    await expect(screen.getByTestId('ai.composer.input')).toHaveValue('[@復習クイズ] ');
  } finally {
    size(previous);
    await device.setAppearance('light');
  }
});
