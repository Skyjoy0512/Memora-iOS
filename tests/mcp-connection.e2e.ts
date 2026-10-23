import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, scrollToControl, tapControl, tapTab } from './ui-helpers';

test('unconnected MCP keeps setup reachable and cancels an unsaved server in Light and Dark', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  try {
    for (const appearance of ['light', 'dark'] as const) {
      await device.setAppearance(appearance);
      await tapTab(screen, 'ツール');
      await tapControl(screen.getByRole('tab', { name: 'コネクタ', exact: true }));
      await tapControl(screen.getByRole('button', { name: 'MCPサーバー', exact: true }));
      const manage = screen.getByText('接続先を管理', { exact: true });
      await scrollToControl(screen, manage);
      await tapControl(manage);
      await expect(screen.getByText('まだ接続先がありません', { exact: true })).toBeVisible();
      await app.screenshot('mcp-unconnected-' + appearance);
      await tapControl(screen.getByRole('button', { name: '接続先を追加', exact: true }));
      await expect(screen.getByPlaceholder('名前（例: Notion）')).toBeVisible();
      await expect(screen.getByPlaceholder('https://…/mcp')).toBeVisible();
      await expect(screen.getByRole('button', { name: '保存', exact: true })).toBeDisabled();
      await expect(screen.getByRole('switch', { name: '料金が発生する、または料金が不明', exact: true })).toBeChecked();
      await app.screenshot('mcp-unsaved-editor-' + appearance);
      await tapControl(screen.getByRole('button', { name: 'キャンセル', exact: true }));
      await expect(screen.getByText('まだ接続先がありません', { exact: true })).toBeVisible();
      await app.restart();
      await expect(screen.getByLabel('メニュー').first()).toBeVisible();
    }
  } finally { await device.setAppearance('light'); }
});
