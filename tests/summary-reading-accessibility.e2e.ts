import { execFileSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { seedSummaryFixture } from './summary-fixture-helpers';
import { sql } from './sqlite-fixture-helpers';
import { scrollToControl } from './ui-helpers';

test('narrow summary supports larger text, horizontal tables, checklist and long reading', { timeout: 360_000 }, async ({ app, device, screen }) => {
  const paragraph = '公開日はまだ確定していません。性能試験と監査承認の両方が終わるまで公開しない条件を維持し、当初案と最新の状態を区別します。';
  const footer = '最終確認では当初案の撤回と、性能試験・監査承認の条件をもう一度照合します。';
  const summary = '## 公開に必要な二つの条件\n' + paragraph +
    '\n\n- [ ] 検証結果を確認する\n- [x] 当初案の撤回を確認した\n\n' +
    '> 性能試験と監査承認の両方を満たすまで公開しない。\n\n' +
    '## 複数案の比較\n| 案 | 効果 | 費用 | 依存関係 | 最後の条件 |\n| --- | --- | --- | --- | --- |\n' +
    '| 段階公開 | 小さく検証する | 150万円 | 監査承認 | 条件を両方満たした場合のみ |\n\n' +
    Array.from({ length: 10 }, (_, i) => `## 検証記録${i + 1}\n${paragraph}`).join('\n\n') +
    '\n\n## 最終状態\n' + footer;
  const { database } = await seedSummaryFixture(app, device, screen, {
    summary, raw: paragraph + footer, segmentID: randomUUID(), timestamp: 12,
  });
  const uuid = database.match(/\/([a-f0-9-]{36})\/data\/Containers\//i)?.[1];
  if (!uuid) throw new Error('Fixture database is not in an identified CoreSimulator device');
  const setSize = (value: string) => execFileSync('xcrun', ['simctl', 'ui', uuid, 'content_size', value], { encoding: 'utf8' }).trim();
  const previous = execFileSync('xcrun', ['simctl', 'ui', uuid, 'content_size'], { encoding: 'utf8' }).trim();
  if (!/^(extra-small|small|medium|large|extra-large|extra-extra-large|extra-extra-extra-large|accessibility-medium|accessibility-large|accessibility-extra-large|accessibility-extra-extra-large|accessibility-extra-extra-extra-large)$/.test(previous)) throw new Error('Unknown content size; refusing to alter a device setting');
  try {
    setSize('large');
    const body = screen.getByRole('button', { name: paragraph, exact: true }).first();
    await expect(body).toBeVisible();
    const normal = await body.boundingBox();
    if (!normal) throw new Error('Missing paragraph bounds');
    expect(normal.x + normal.width).toBeLessThanOrEqual(402);
    await app.screenshot('summary-narrow-normal');
    setSize('accessibility-large');
    await expect.poll(async () => (await body.boundingBox())?.height ?? 0).toBeGreaterThan(normal.height * 1.2);
    await scrollToControl(screen, body);
    await device.setAppearance('dark');
    await app.screenshot('summary-narrow-accessibility-dark');
    await expect(screen.getByTestId('ai.composer.input')).toBeVisible();
    setSize('large');
    await device.setAppearance('light');
    const check = screen.getByRole('button', { name: /検証結果を確認する/ }).first();
    await scrollToControl(screen, check);
    await expect(check).toBeVisible();
    const first = screen.getByRole('button', { name: '案', exact: true }).first();
    await scrollToControl(screen, first);
    const bounds = await first.boundingBox();
    if (!bounds) throw new Error('Missing table bounds');
    await screen.swipe({ from: { x: 360, y: bounds.y + bounds.height / 2 }, to: { x: 60, y: bounds.y + bounds.height / 2 }, duration: 500 });
    await expect(screen.getByRole('button', { name: '最後の条件', exact: true })).toBeVisible();
    await app.screenshot('summary-narrow-horizontal-table');
    const end = screen.getByRole('button', { name: footer, exact: true });
    await scrollToControl(screen, end);
    await expect(end).toBeVisible();
    await expect(screen.getByTestId('ai.composer.input')).toBeVisible();
    await app.screenshot('summary-long-final-state');
    const stored = JSON.parse(sql(database, "SELECT CAST(data AS TEXT) FROM documents WHERE key='memoraMeetings';"));
    expect(stored[0].summary).toBe(summary);
    expect(stored[0].transcript[0].text).toBe(paragraph + footer);
  } finally {
    setSize(previous);
    await device.setAppearance('light');
  }
});
