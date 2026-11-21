import { afterEach, test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { focusComposer, launchMemora, selectLibrarySection, tapControl, tapTab } from './ui-helpers';

const destinations = ['ライブラリ', 'ジャーナル', 'Ask AI'];

afterEach(async ({ device }) => { await device.setAppearance('light'); });

test('native tabs keep three accessible destinations below the composer', { timeout: 120_000 }, async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  const tabs = destinations.map(name => screen.getByRole('tab', { name, exact: true }));
  const input = screen.getByTestId('ai.composer.input');
  const capture = screen.getByRole('button', { name: '追加メニュー', exact: true });
  await expect(tabs[0]).toBeSelected();

  for (const appearance of ['light', 'dark'] as const) {
    await device.setAppearance(appearance);
    for (const [index, name] of destinations.entries()) {
      await tapTab(screen, name);
      await expect(screen.getByRole('tab')).toHaveCount(3);
      await expect(tabs[index]).toBeSelected();
      await expect(input).toBeVisible();
      if (index === 2) await expect(capture).not.toBeVisible();
      else await expect(capture).toBeVisible();
      const frames = await Promise.all(tabs.map(tab => tab.boundingBox()));
      const field = await input.boundingBox();
      const [first, second, third] = frames;
      if (!field || !first || !second || !third) throw new Error('Missing tab or composer frame');
      const centers = [first, second, third].map(frame => frame.x + frame.width / 2);
      expect(centers[1] - centers[0]).toBeGreaterThan(44);
      expect(centers[2] - centers[1]).toBeCloseTo(centers[1] - centers[0], 0);
      expect(field.y + field.height).toBeLessThan(first.y);
      await app.screenshot(`root-${index}-${appearance}`);
    }
  }
});

test('native tabs preserve the project workspace and keep AI scope local to each destination', { timeout: 120_000 }, async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await selectLibrarySection(screen, 'プロジェクト');
  await tapControl(screen.getByRole('button', { name: 'プロジェクトを作成' }).first());
  const title = 'ナビゲーション検証';
  await screen.getByPlaceholder('例：新規アプリ').fill(title);
  await tapControl(screen.getByRole('button', { name: '作成', exact: true }));
  await expect(screen.getByText(title, { exact: true }).first()).toBeVisible();
  const input = screen.getByTestId('ai.composer.input');
  await expect(input).toHaveValue('このプロジェクトに質問');
  await expect(screen.getByRole('button', { name: '記録', exact: true, selected: true })).toBeVisible();
  await tapControl(screen.getByRole('button', { name: '参考資料', exact: true }));
  await app.screenshot('project-references');

  await tapTab(screen, 'ジャーナル');
  await expect(input).toHaveValue('Memoraに質問');
  await tapTab(screen, 'Ask AI');
  await expect(input).toHaveValue('Memoraに話しかける');
  await tapTab(screen, 'ライブラリ');
  await expect(screen.getByText(title, { exact: true }).first()).toBeVisible();
  await expect(screen.getByRole('button', { name: '参考資料', exact: true, selected: true })).toBeVisible();
  await expect(input).toHaveValue('このプロジェクトに質問');
});

test('native tabs yield to the keyboard and restore the Ask AI draft on return', { timeout: 120_000 }, async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapTab(screen, 'Ask AI');
  const input = await focusComposer(screen);
  await expect(screen.getByRole('keyboard')).toBeVisible();
  await expect(screen.getByRole('tab')).toHaveCount(0);
  const draft = '画面を移動しても保持する下書き';
  await input.fill(draft);
  await expect(input).toHaveValue(draft);
  await app.screenshot('ask-ai-with-keyboard');

  await screen.tapAt({ x: 215, y: 130 });
  await expect(screen.getByRole('keyboard')).not.toBeVisible();
  await tapTab(screen, 'ジャーナル');
  await tapTab(screen, 'Ask AI');
  await expect(input).toHaveValue(draft);
  await app.restart();
  await tapTab(screen, 'Ask AI');
  await expect(input).toHaveValue(draft);
});
