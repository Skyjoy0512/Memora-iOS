import { afterEach, test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, scrollToControl, tapControl } from './ui-helpers';

afterEach(async ({ device }) => { await device.setAppearance('light'); });

async function openSettings(screen: any) {
  await tapControl(screen, screen.getByLabel('メニュー'));
  await tapControl(screen, screen.getByRole('button', { name: '設定', exact: true }).last());
  await expect(screen.getByTestId('settings.profile').first()).toBeVisible();
}

async function category(screen: any, id: string) {
  // Returning from a category keeps the root list's scroll position.
  for (let i = 0; i < 4 && !(await screen.getByTestId('settings.profile').first().isVisible()); i++) {
    await screen.swipe({ from: { x: 215, y: 300 }, to: { x: 215, y: 730 }, duration: 500 });
  }
  const row = screen.getByTestId(`settings.category.${id}`).first();
  await scrollToControl(screen, row);
  await tapControl(screen, row);
}

async function back(screen: any) {
  await tapControl(screen, screen.getByTestId('BackButton'));
}

test('settings polish: topic hierarchy, profile editing and shared sidebar icons', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  for (const appearance of ['light', 'dark'] as const) {
    await device.setAppearance(appearance);
    await tapControl(screen, screen.getByLabel('メニュー'));
    await expect(screen.getByLabel('ワークスペース', { exact: true })).not.toBeVisible();
    await app.screenshot(`sidebar-top-${appearance}`);
    // The drawer's destination follows the same-named Library segment in AX.
    await scrollToControl(screen, screen.getByRole('button', { name: 'プロジェクト', exact: true }).last());
    await expect(screen.getByText('プロジェクト', { exact: true }).last()).toBeVisible();
    await scrollToControl(screen, screen.getByRole('button', { name: '人物', exact: true }));
    await expect(screen.getByText('人物', { exact: true })).toBeVisible();
    await expect(screen.getByRole('button', { name: 'Memora Plus、プランと利用状況', exact: true })).toBeVisible();
    await app.screenshot(`sidebar-${appearance}`);
    const recorder = screen.getByText('外部レコーダー', { exact: true });
    await scrollToControl(screen, recorder);
    const titleBox = await recorder.boundingBox();
    if (!titleBox) throw new Error('recorder title has no frame');
    // A narrow title/status split must not turn Japanese into one-character columns.
    expect(titleBox.height).toBeLessThanOrEqual(titleBox.width * 2);
    await app.screenshot(`sidebar-devices-${appearance}`);
    await tapControl(screen, screen.getByRole('button', { name: '設定', exact: true }).last());
    await expect(screen.getByRole('switch')).not.toBeVisible();
    await expect(screen.getByText('Gmail', { exact: true })).not.toBeVisible();
    await expect(screen.getByText('AIモデル', { exact: true })).not.toBeVisible();
    await app.screenshot(`settings-topics-${appearance}`);
    for (const id of ['account', 'workspace', 'plan', 'recording', 'ai', 'journal', 'integrations', 'appearance', 'privacy', 'data', 'about', 'diagnostics']) {
      const row = screen.getByTestId(`settings.category.${id}`).first();
      await scrollToControl(screen, row);
      const box = await row.boundingBox();
      expect(box?.height).toBeGreaterThanOrEqual(44);
    }
    await app.screenshot(`settings-topics-bottom-${appearance}`);
    await tapControl(screen, screen.getByRole('button', { name: '閉じる', exact: true }));
  }
  await device.setAppearance('light');
  await openSettings(screen);
  await tapControl(screen, screen.getByTestId('settings.profile').first());
  await expect(screen.getByPlaceholder('表示する名前')).toBeVisible();
  await expect(screen.getByRole('button', { name: 'ミー文字・絵文字を選ぶ', exact: true }).first()).toBeVisible();
});

test('settings polish: personal workspace stays selectable and unavailable team setup is explained', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapControl(screen, screen.getByLabel('メニュー'));
  await expect(screen.getByRole('button', { name: 'ライブラリ', exact: true })).toBeVisible();
  await expect(screen.getByLabel('ワークスペース', { exact: true })).not.toBeVisible();
  await tapControl(screen, screen.getByRole('button', { name: '設定', exact: true }).last());
  await expect(screen.getByTestId('settings.profile').first()).toBeVisible();
  await category(screen, 'workspace');
  const workspace = screen.getByTestId('workspace.option.personal');
  await expect(workspace).toBeVisible();
  await expect(workspace).toBeSelected();
  await tapControl(screen, workspace);
  await expect(workspace).toBeSelected();
  await expect(screen.getByText('チームの作成と参加は、サービス接続後に利用できます。')).toBeVisible();
  await expect(screen.getByRole('button', { name: 'チームに参加', exact: true })).not.toBeVisible();
  await app.screenshot('workspace-team-unavailable');
});

test('settings polish: demo replacement needs explicit destructive confirmation', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await openSettings(screen);
  await category(screen, 'diagnostics');
  const replace = screen.getByRole('button', { name: 'デモデータに置き換える', exact: true });
  await scrollToControl(screen, replace);
  await tapControl(replace);
  await expect(screen.getByText('既存の内容をデモデータに置き換えますか？', { exact: true })).toBeVisible();
  await tapControl(screen.getByRole('button', { name: 'キャンセル', exact: true }));
  await expect(replace).toBeVisible();
});

test('settings polish: appearance preferences survive restart without changing records', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await openSettings(screen);
  await category(screen, 'appearance');
  const dark = screen.getByRole('switch', { name: 'ダークモード', exact: true });
  const haptics = screen.getByRole('switch', { name: '触覚フィードバック', exact: true });
  await expect(dark).not.toBeChecked();
  await expect(haptics).toBeChecked();
  await tapControl(screen, dark);
  await tapControl(screen, haptics);
  await expect(dark).toBeChecked();
  await expect(haptics).not.toBeChecked();
  await app.screenshot('appearance-preferences-dark');
  await app.restart();
  await openSettings(screen);
  await category(screen, 'appearance');
  await expect(dark).toBeChecked();
  await expect(haptics).not.toBeChecked();
  await tapControl(screen, dark);
  await tapControl(screen, haptics);
});

test('settings polish: relocated AI, recording, plan and connection controls remain reachable', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await openSettings(screen);
  await category(screen, 'plan');
  await expect(screen.getByText('購入は未接続です。プランの変更は端末の設定のみで、課金されません。')).toBeVisible();
  await expect(screen.getByText('AIクレジット', { exact: true })).toBeVisible();
  await expect(screen.getByText('法人ライセンス', { exact: true })).toBeVisible();
  await back(screen);
  await category(screen, 'recording');
  await expect(screen.getByText('声のプロフィール', { exact: true })).toBeVisible();
  await expect(screen.getByText('話者識別', { exact: true })).toBeVisible();
  await expect(screen.getByText('外部レコーダー', { exact: true })).toBeVisible();
  await app.screenshot('recording-topic');
  await back(screen);
  await category(screen, 'ai');
  await expect(screen.getByText('AIモデル', { exact: true })).toBeVisible();
  await expect(screen.getByText('要約テンプレート', { exact: true })).toBeVisible();
  await expect(screen.getByText('スキル', { exact: true })).toBeVisible();
  await app.screenshot('ai-topic');
  await back(screen);
  await category(screen, 'integrations');
  await expect(screen.getByText('Gmail', { exact: true })).toBeVisible();
  await expect(screen.getByText('スキル', { exact: true })).not.toBeVisible();
  await app.screenshot('integrations-topic');
  await tapControl(screen, screen.getByText('Gmail', { exact: true }));
  await expect(screen.getByTestId('connector.requirement')).toBeVisible();
  await tapControl(screen, screen.getByRole('button', { name: '接続', exact: true }));
  await expect(screen.getByText(/Google OAuth|クライアントID|接続されていません|Gmailを接続/).first()).toBeVisible();
  await back(screen);
  await back(screen);
  await tapControl(screen, screen.getByText('Google Drive', { exact: true }));
  await expect(screen.getByText('このサービスとの連携は準備中です。')).toBeVisible();
});
