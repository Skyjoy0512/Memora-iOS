import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, scrollToControl, tapControl, tapTab } from './ui-helpers';

// This build has no OAuth client ID. Do not sign in or seed fake credentials.
test('unconfigured Gmail stays disconnected and explains read-only access in Light and Dark', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  try {
    for (const appearance of ['light', 'dark'] as const) {
      await device.setAppearance(appearance);
      await tapTab(screen, 'ツール');
      await tapControl(screen.getByRole('tab', { name: 'コネクタ', exact: true }));
      await tapControl(screen.getByRole('button', { name: 'Gmail', exact: true }));
      await expect(screen.getByText('読み取り専用。取得した内容は選択中のAIに渡されます。', { exact: true })).toBeVisible();
      const setup = screen.getByText('接続・認証設定', { exact: true });
      await scrollToControl(screen, setup);
      await tapControl(setup);
      const connect = screen.getByRole('button', { name: 'Gmailと連携', exact: true });
      await expect(connect).toBeVisible();
      await expect(connect).toBeDisabled();
      await expect(screen.getByText('このビルドにはGoogleのOAuthクライアントIDがまだ設定されていません。設定されるまで連携できません。', { exact: true })).toBeVisible();
      await expect(screen.getByRole('button', { name: '連携を解除', exact: true })).not.toBeVisible();
      await expect(screen.getByText('連携中のアカウント', { exact: true })).not.toBeVisible();
      await app.screenshot('gmail-unconfigured-' + appearance);
      await app.restart();
      await expect(screen.getByLabel('メニュー').first()).toBeVisible();
    }
  } finally { await device.setAppearance('light'); }
});
