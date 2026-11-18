import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, openSettingsGallery, scrollToControl, tapControl } from './ui-helpers';

// The bundled example exercises the production answer renderer without a model request.
for (const mode of ['フォーム', '長文']) {
  test(`answer layout: ${mode} remains readable through the end`, { timeout: 180_000 }, async ({ app, device, screen }) => {
    await device.setAppearance('light');
    try {
      await launchMemora(app, device, screen);
      await tapControl(screen.getByLabel('メニュー'));
      await tapControl(screen.getByTestId('sidebar.settings'));
      await openSettingsGallery(screen);
      const example = screen.getByRole('button', { name: '生成UI（フォームと操作）', exact: true });
      await scrollToControl(screen, example);
      await tapControl(example);
      if (mode === '長文') await tapControl(screen.getByRole('tab', { name: '長文', exact: true }));
      await expect(screen.getByText('操作できる回答', { exact: true })).toBeVisible();
      await app.screenshot('generated-answer-top-light');
      const prose = screen.getByText('表示検証用の架空データです。入力や操作はこの回答の中だけで動きます。', { exact: true });
      const title = screen.getByText('操作できる回答', { exact: true });
      const separation = async () => {
        const [proseBox, titleBox] = await Promise.all([prose.boundingBox(), title.boundingBox()]);
        if (!proseBox || !titleBox) throw new Error('answer text must retain measurable frames');
        return titleBox.y - proseBox.y;
      };
      const initialSeparation = await separation();
      await screen.swipe({ from: { x: 220, y: 700 }, to: { x: 220, y: 640 }, duration: 600 });
      // Dragging inside the generated UI must move it with the preceding prose.
      await expect.poll(async () => Math.abs(await separation() - initialSeparation)).toBeLessThanOrEqual(4);
      const finalAction = screen.getByRole('button', { name: '入力した名前をコピー', exact: true });
      await scrollToControl(screen, finalAction);
      await expect(finalAction).toBeVisible();
      await app.screenshot('generated-answer-end-light');
      await device.setAppearance('dark');
      await expect(finalAction).toBeVisible();
      await app.screenshot('generated-answer-end-dark');
      await device.setAppearance('light');
      await tapControl(screen.getByRole('button', { name: 'ダイアログを開く', exact: true }));
      await expect(screen.getByText('確認用ダイアログ', { exact: true }).first()).toBeVisible();
      await expect(screen.getByText('本家のDialogコンポーネントです。', { exact: true })).toBeVisible();
      await app.screenshot('generated-answer-dialog');
      await tapControl(screen.getByRole('button', { name: 'Close', exact: true }));
      await expect(screen.getByText('確認用ダイアログ', { exact: true })).not.toBeVisible();
      if (mode === '長文') {
        await device.setAppearance('dark');
        await tapControl(finalAction);
        await expect(screen.getByText('コピー前の確認', { exact: true }).first()).toBeVisible();
        await app.screenshot('generated-answer-confirmation-dark');
        await tapControl(screen.getByRole('button', { name: 'キャンセル', exact: true }));
        await expect(screen.getByText('コピー前の確認', { exact: true })).not.toBeVisible();
        await device.setAppearance('light');
      }
      await tapControl(screen.getByRole('switch', { name: '補足を表示', exact: true }));
      await expect(screen.getByText('スイッチでこの補足の表示が切り替わります。', { exact: true })).not.toBeVisible();
      await scrollToControl(screen, finalAction, { minimumY: 150, maximumY: 880 });
      // A shorter DOM must shrink its native frame, rather than retain blank space.
      await expect.poll(async () => {
        const [web, action] = await Promise.all([
          screen.getByRole('web-view', { name: '操作できる生成回答', exact: true }).boundingBox(),
          finalAction.boundingBox(),
        ]);
        if (!web || !action) return Infinity;
        return Math.abs(web.y + web.height - action.y - action.height);
      }).toBeLessThanOrEqual(40);
      await app.screenshot('generated-answer-collapsed');
    } finally { await device.setAppearance('light'); }
  });
}
