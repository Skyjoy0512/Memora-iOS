import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, scrollToControl, tapControl, tapTab, selectLibrarySection } from './ui-helpers';

async function openDiagnostics(screen: any) {
  await tapControl(screen.getByLabel('メニュー').first());
  await tapControl(screen.getByTestId('sidebar.settings'));
  const diagnostics = screen.getByTestId('settings.category.diagnostics');
  await scrollToControl(screen, diagnostics);
  await tapControl(diagnostics);
}

async function addSamples(screen: any) {
  await openDiagnostics(screen);
  await tapControl(screen.getByTestId('screenReview.samples.add'));
}

test('screen review samples persist without replacing existing content or duplicating states', { timeout: 300_000 }, async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await openDiagnostics(screen);
  await tapControl(screen.getByTestId('summary.sample.open'));
  await tapControl(screen.getByTestId('BackButton'));
  const original = screen.getByRole('button', { name: /^発売準備ミーティング（サンプル）、/ });
  await expect(original).toBeVisible();
  await addSamples(screen);
  const first = screen.getByRole('button', { name: /^01 文字起こし前（サンプル）、/ });
  await expect(first).toBeVisible();
  await addSamples(screen);
  await screen.swipe({ from: { x: 220, y: 300 }, to: { x: 220, y: 750 }, duration: 500 });
  await screen.swipe({ from: { x: 220, y: 300 }, to: { x: 220, y: 750 }, duration: 500 });
  await expect(first).toBeVisible();
  await expect(first).toHaveCount(1);
  await app.restart();
  await expect(first).toBeVisible();
  await app.screenshot('screen-review-library');

  const states = [
    ['01 文字起こし前', '文字起こしする'], ['02 要約前', '要約する'],
    ['03 取り込み中', '準備しています'], ['04 文字起こし中', '準備しています'],
    ['05 要約中', '準備しています'], ['06 要約済み', ''],
    ['07 文字起こし失敗', 'もう一度試す'], ['08 要約失敗', '要約を再試行'],
  ];
  for (const [title, action] of states) {
    const row = screen.getByRole('button', { name: new RegExp(`^${title}（サンプル）、`) });
    await scrollToControl(screen, row);
    await tapControl(row);
    await expect(screen.getByText('記録', { exact: true }).first()).toBeVisible();
    await expect(screen.getByText(title + '（サンプル）', { exact: true }).last()).toBeVisible();
    if (action === '準備しています') await expect(screen.getByTestId('ai.waitingStatus')).toBeVisible();
    else if (action) await expect(screen.getByRole('button', { name: action, exact: true })).toBeVisible();
    await app.screenshot('screen-review-state-' + title.slice(0, 2));
    if (title === '02 要約前') {
      await tapControl(screen.getByRole('button', { name: '文字起こし', exact: true }));
      await expect(screen.getByText(/次のリリースでは、録音を始めるまでの迷い/).first()).toBeVisible();
      await app.screenshot('screen-review-transcript');
      await tapControl(screen.getByTestId('transcript.search'));
      await screen.getByTestId('transcript.search.input').fill('存在しない発言xyz');
      await expect(screen.getByText('一致する発言はありません', { exact: true })).toBeVisible();
      await screen.getByTestId('transcript.search.input').fill('録音');
      await expect(screen.getByText(/次のリリースでは、録音を始めるまでの迷い/).first()).toBeVisible();
      await tapControl(screen.getByRole('button', { name: '検索を閉じる', exact: true }));
      await tapControl(screen.getByRole('button', { name: 'ノート', exact: true }));
      await expect(screen.getByText(/画面確認用の架空データです。音声ファイルは含みません/).first()).toBeVisible();
    }
    await tapControl(screen.getByTestId('BackButton'));
  }
  await scrollToControl(screen, original);
  await expect(original).toBeVisible();
  await tapTab(screen, 'ジャーナル');
  const journalEntry = screen.getByRole('button', { name: /08 要約失敗（サンプル）/ });
  await expect(journalEntry).toBeVisible();
  await app.screenshot('screen-review-journal');
  await expect(screen.getByText('この間に記録を追加', { exact: true })).not.toBeVisible();
  await tapTab(screen, 'ライブラリ');
  await selectLibrarySection(screen, 'プロジェクト');
  await tapControl(screen.getByRole('button', { name: /^画面確認（サンプル）、/ }));
  await expect(screen.getByTestId('project.workspace.sections')).toBeVisible();
  await expect(screen.getByRole('button', { name: /^01 文字起こし前（サンプル）、/ })).toBeVisible();
  await app.screenshot('screen-review-project-records-first');
  await tapControl(screen.getByRole('button', { name: 'チャット', exact: true }));
  await expect(screen.getByText('チャットを始める', { exact: true })).toBeVisible();
  await tapControl(screen.getByRole('button', { name: '参考資料', exact: true }));
  await expect(screen.getByRole('button', { name: '参考資料を追加', exact: true }).last()).toBeVisible();
});
