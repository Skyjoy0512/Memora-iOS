import { afterEach, test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { randomUUID } from 'node:crypto';
import { seedSummaryFixture } from './summary-fixture-helpers';
import { sql } from './sqlite-fixture-helpers';
import { focusComposer, launchMemora, requireRootMenu, selectLibrarySection, tapControl, tapTab } from './ui-helpers';

const destinations = [
  { name: 'ライブラリ', id: 'files' },
  { name: 'ジャーナル', id: 'home' },
  { name: 'Ask AI', id: 'askAI' },
];
const rootTabs = /^root\.tab\./;

afterEach(async ({ device }) => { await device.setAppearance('light'); });

test('bottom tabs keep three equally spaced destinations below the composer', { timeout: 120_000 }, async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  const tabs = destinations.map(({ id }) => screen.getByTestId(`root.tab.${id}`));
  const input = screen.getByTestId('ai.composer.input');
  const capture = screen.getByRole('button', { name: '追加メニュー', exact: true });
  await expect(tabs[0]).toBeSelected();

  for (const appearance of ['light', 'dark'] as const) {
    await device.setAppearance(appearance);
    for (const [index, { name }] of destinations.entries()) {
      await tapTab(screen, name);
      await expect(screen.getByTestId(rootTabs)).toHaveCount(3);
      await expect(tabs[index]).toBeSelected();
      await expect(input).toBeVisible();
      if (index === 2) await expect(capture).not.toBeVisible();
      else await expect(capture).toBeVisible();
      const frames = await Promise.all(tabs.map(tab => tab.boundingBox()));
      const field = await input.boundingBox();
      const [first, second, third] = frames;
      if (!field || !first || !second || !third) throw new Error('Missing tab or composer frame');
      const centers = [first, second, third].map(frame => frame.x + frame.width / 2);
      expect(centers[1] - centers[0]).toBeCloseTo(64, 0);
      expect(centers[2] - centers[1]).toBeCloseTo(64, 0);
      if (index === 2) expect(centers[1]).toBeCloseTo(field.x + field.width / 2, -1);
      expect(field.y + field.height).toBeLessThan(first.y);
      await app.screenshot(`root-${index}-${appearance}`);
    }
  }
});

test('bottom tabs preserve the project workspace and keep AI scope local to each destination', { timeout: 120_000 }, async ({ app, device, screen }) => {
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

test('bottom tabs yield to the keyboard and restore the Ask AI draft on return', { timeout: 120_000 }, async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapTab(screen, 'Ask AI');
  const input = await focusComposer(screen);
  await expect(screen.getByRole('keyboard')).toBeVisible();
  await expect(screen.getByTestId(rootTabs)).toHaveCount(0);
  const draft = '画面を移動しても保持する下書き';
  await input.fill(draft);
  await expect(input).toHaveValue(draft);
  await app.screenshot('ask-ai-with-keyboard');

  await tapControl(screen.getByTestId('ai.composer.model'));
  await expect(screen.getByText('モデルを選択', { exact: true }).first()).toBeVisible();
  await expect(screen.getByRole('button', { name: /^Auto/, selected: true })).toBeVisible();
  await app.screenshot('ask-ai-model-sheet');
  await tapControl(screen.getByRole('button', { name: '閉じる', exact: true }));
  await expect(input).toBeFocused();
  await expect(input).toHaveValue(draft);
  await expect(screen.getByTestId(rootTabs)).toHaveCount(0);

  await screen.tapAt({ x: 215, y: 130 });
  await expect(screen.getByRole('keyboard')).not.toBeVisible();
  await tapTab(screen, 'ジャーナル');
  await tapTab(screen, 'Ask AI');
  await expect(input).toHaveValue(draft);
  await app.restart();
  await tapTab(screen, 'Ask AI');
  await expect(input).toHaveValue(draft);
});

test('bottom tabs temporarily give Library search the full screen', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapControl(screen.getByRole('button', { name: 'ファイルを検索', exact: true }));
  const query = screen.getByTestId('collection.search.input');
  await expect(query).toBeFocused();
  await expect(screen.getByTestId(rootTabs)).toHaveCount(0);
  await expect(screen.getByTestId('ai.composer.input')).not.toBeVisible();
  await query.fill('一致しない記録');
  await expect(screen.getByText('見つかりませんでした', { exact: true }).first()).toBeVisible();
  await app.screenshot('library-search');
  await tapControl(screen.getByTestId('collection.search.cancel'));
  await expect(screen.getByTestId('root.tab.files')).toBeSelected();
  await expect(screen.getByTestId('ai.composer.input')).toBeVisible();
});

test('bottom tabs and the keyboard preserve the reading position in a long answer', { timeout: 180_000 }, async ({ app, device, screen }) => {
  const { database } = await seedSummaryFixture(app, device, screen);
  const createdAt = Date.now() / 1000 - 978307200;
  const turn = (role: 'user' | 'assistant', text: string) => ({
    id: randomUUID(), role, text, createdAt, wasInterrupted: false, didChangeData: false,
    pluginIDs: [], sources: [], documentIDs: [], webResearchReportIDs: [], suggestions: [],
  });
  const end = 'ここまでが検証用の回答です。';
  const sections = Array.from({ length: 24 }, (_, index) =>
    `## 確認事項 ${index + 1}\n\n担当と期日を記録で確認します。変更を反映する前に出典を読み返します。`);
  const snapshot = { version: 1, turns: [
    turn('user', '確認事項を読みたいです。'),
    turn('assistant', [...sections, end].join('\n\n')),
  ] };
  await device.closeApp();
  const data = Buffer.from(JSON.stringify(snapshot)).toString('hex');
  sql(database, `INSERT OR REPLACE INTO documents(key,data,updated_at) VALUES ('memora.activeAIConversation.v1.personal',X'${data}',0);`);
  await app.restart();
  await requireRootMenu(app, screen);
  await tapTab(screen, 'Ask AI');
  const latest = screen.getByText(end, { exact: true }).first();
  await expect(latest).toBeVisible();
  const input = screen.getByTestId('ai.composer.input');
  const tail = await latest.boundingBox();
  const composer = await input.boundingBox();
  if (!tail || !composer) throw new Error('Missing reply or composer frame');
  expect(tail.y + tail.height).toBeLessThan(composer.y);
  await screen.swipe({ from: { x: 215, y: 300 }, to: { x: 215, y: 680 }, duration: 480 });
  await expect(latest).not.toBeVisible();
  await focusComposer(screen);
  await expect(latest).not.toBeVisible();
  await screen.tapAt({ x: 215, y: 130 });
  await expect(screen.getByRole('keyboard')).not.toBeVisible();
  await expect(latest).not.toBeVisible();
  await tapTab(screen, 'ジャーナル');
  await tapTab(screen, 'Ask AI');
  await expect(latest).not.toBeVisible();
  await app.screenshot('ask-ai-reading-position');
});
