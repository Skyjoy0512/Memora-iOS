import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, tapControl } from './ui-helpers';

test('top-right audio picker cancellation preserves Library capture and native morph', { timeout: 240_000 }, async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  try {
    for (const appearance of ['light', 'dark'] as const) {
      await device.setAppearance(appearance);
      await tapControl(screen.getByLabel('新規作成').first());
      await expect(screen.getByRole('button', { name: '録音を開始', exact: true })).toBeVisible();
      await app.screenshot('audio-picker-capture-' + appearance);
      const importAudio = screen.getByRole('button', { name: 'ファイルをインポート', exact: true });
      await tapControl(importAudio);
      await expect(screen.getByTestId('FullDocumentManagerViewControllerNavigationBar')).toBeVisible();
      const cancel = screen.getByRole('button', { name: /^(Cancel|キャンセル)$/ }).first();
      await tapControl(cancel);
      await expect(screen.getByTestId('FullDocumentManagerViewControllerNavigationBar')).not.toBeVisible();
      if (!(await importAudio.isVisible())) await tapControl(screen.getByLabel('新規作成').first());
      await expect(screen.getByRole('button', { name: '録音を開始', exact: true })).toBeVisible();
      await expect(screen.getByText('インポートできませんでした', { exact: true })).not.toBeVisible();
      await tapControl(screen.getByRole('button', { name: 'メモを作成', exact: true }));
      await expect(screen.getByPlaceholder('メモのタイトル')).toBeVisible();
      await tapControl(screen.getByLabel('キャンセル', { exact: true }));
      await expect(screen.getByRole('button', { name: 'ファイル', exact: true, selected: true })).toBeVisible();
    }
  } finally { await device.setAppearance('light'); }
});
