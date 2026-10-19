import { afterEach, test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { focusComposer, launchMemora, tapControl } from './ui-helpers';

afterEach(async ({ device }) => { await device.setAppearance('light'); });

async function openReview(device: any, screen: any) {
  await device.openLink('memora://journal');
  await tapControl(screen, screen.getByLabel('メニュー'));
  await tapControl(screen, screen.getByRole('button', { name: '設定', exact: true }).last());
  await expect(screen.getByText('アカウント')).toBeVisible();
  const gallery = screen.getByRole('button', { name: '状態と復旧UIを確認', exact: true });
  for (let attempt = 0; attempt < 9 && !(await gallery.isVisible()); attempt++) {
    await screen.swipe({ from: { x: 215, y: 700 }, to: { x: 215, y: 300 }, duration: 500 });
  }
  await tapControl(screen, gallery);
  await tapControl(screen, screen.getByText('デザインと保存の検証'));
}

test('polish: candidate names, selected state and keyboard survive appearance changes', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await device.openLink('memora://ask-ai');
  const confirmation = screen.getByRole('button', { name: '開く', exact: true });
  if (await confirmation.isVisible()) await confirmation.tap();
  const input = await focusComposer(screen);
  await input.fill('@file');
  const files = screen.getByRole('button', { name: 'ファイル・記録の検索、利用可能', exact: true });
  await expect(files).toBeVisible();
  await expect(files).toHaveValue('端末内処理');
  await expect.poll(async () => {
    const row = await files.boundingBox();
    // SwiftUI propagates this container identifier to its descendants as well.
    const menu = await screen.getByTestId('ai.mention.candidates').first().boundingBox();
    return Boolean(row && menu && row.y + row.height <= menu.y + menu.height + 1);
  }).toBe(true);
  await app.screenshot('candidates-light');
  await device.setAppearance('dark');
  await expect(files).toBeVisible();
  await expect(screen.getByRole('keyboard')).toBeVisible();
  await app.screenshot('candidates-dark');
  await tapControl(screen, files);
  await expect(input).toHaveValue(/\[@ファイル・記録の検索\]/);
  await input.pressSequentially('@file');
  const selected = screen.getByRole('button', { name: 'ファイル・記録の検索、利用可能', exact: true, selected: true });
  await expect(selected).toBeVisible();
  await app.screenshot('candidate-selected');
  await tapControl(screen, screen.getByLabel('候補を閉じる'));
  await expect(screen.getByRole('keyboard')).toBeVisible();
  await expect(screen.getByLabel('ファイル・記録の検索の指定を削除')).toBeVisible();
});

test('polish: library metadata and status remain readable in both appearances', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await openReview(device, screen);
  await tapControl(screen, screen.getByText('検証データを片付ける'));
  await tapControl(screen, screen.getByText('検証用の要約を作成'));
  await expect(screen.getByText('検証用の要約を保存しました')).toBeVisible();
  await device.openLink('memora://projects');
  await tapControl(screen, screen.getByRole('button', { name: 'ファイル', exact: true }).first());
  for (const appearance of ['light', 'dark'] as const) {
    await device.setAppearance(appearance);
    await expect(screen.getByText('QA デザイン検証の要約')).toBeVisible();
    await expect(screen.getByText('整理済み')).toBeVisible();
    await app.screenshot(`library-fixture-${appearance}`);
  }
  await device.setAppearance('light');
  await openReview(device, screen);
  await tapControl(screen, screen.getByText('検証データを片付ける'));
  await expect(screen.getByText('検証データを削除しました')).toBeVisible();
});
