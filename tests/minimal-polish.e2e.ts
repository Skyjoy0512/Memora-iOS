import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, tapControl, tapTab } from './ui-helpers';

test('minimal polish: Tools menus, article actions and connectors stay usable', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapTab(screen, 'ツール');
  const add = screen.getByLabel('ツールを追加');
  await tapControl(screen, add);
  await tapControl(screen, screen.getByRole('button', { name: 'スキルを作成', exact: true }));
  await expect(screen.getByPlaceholder('スキル名')).toBeVisible();
  await tapControl(screen, screen.getByRole('button', { name: 'キャンセル', exact: true }));
  await expect(add).toBeVisible();
  await tapControl(screen, screen.getByRole('button', { name: /プロジェクトの要点整理/ }));
  await expect(screen.getByText('目的とシナリオ', { exact: true })).toBeVisible();
  const use = screen.getByRole('button', { name: 'チャットで使用', exact: true });
  const box = await use.boundingBox();
  expect(box?.height).toBeGreaterThanOrEqual(44);
  expect(box?.height).toBeLessThanOrEqual(60);
  await app.screenshot('minimal-skill-article');
  await tapControl(screen, screen.getByLabel('スキルの操作'));
  await expect(screen.getByRole('button', { name: 'Markdownを共有', exact: true })).toBeVisible();
  await screen.tapAt({ x: 160, y: 200 });
  await tapControl(screen, screen.getByLabel('1つ前に戻る'));
  await tapControl(screen, screen.getByRole('tab', { name: 'コネクタ', exact: true }));
  await app.screenshot('minimal-connectors');
  await tapControl(screen, screen.getByRole('button', { name: 'Gmail', exact: true }));
  await expect(screen.getByText('読み取り専用。取得した内容は選択中のAIに渡されます。', { exact: true })).toBeVisible();
});
