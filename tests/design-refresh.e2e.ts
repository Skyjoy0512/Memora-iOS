import { afterEach, test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { focusComposer, launchMemora, tapControl as tap, tapTab as tab, openSettingsGallery } from './ui-helpers';

async function openLink(device: any, screen: any, url: string) {
  await device.openLink(url);
  const confirmation = screen.getByRole('button', { name: '開く', exact: true });
  if (await confirmation.isVisible()) await tap(screen, confirmation);
}

async function fillComposer(screen: any, text: string) {
  const input = await focusComposer(screen);
  // The focused native field expands. Resolve its new frame before filling.
  await input.fill(text);
  return input;
}

async function scrollTo(screen: any, locator: any) {
  for (let i = 0; i < 9; i++) {
    if (await locator.isVisible()) return;
    await screen.swipe({ from: { x: 215, y: 700 }, to: { x: 215, y: 300 }, duration: 500 });
  }
  throw new Error('target not reached');
}

async function review(screen: any, device: any) {
  await openLink(device, screen, 'memora://journal');
  await tap(screen, screen.getByLabel('メニュー'));
  await tap(screen, screen.getByRole('button', { name: '設定', exact: true }).last());
  await expect(screen.getByText('アカウント').first()).toBeVisible();
  await openSettingsGallery(screen);
  await tap(screen, screen.getByText('デザインと保存の検証'));
}

afterEach(async ({ device }) => {
  await device.setAppearance('light');
});

test('design: navigation and settings in light and dark', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  for (const appearance of ['light', 'dark'] as const) {
    await device.setAppearance(appearance);
    await openLink(device, screen, 'memora://journal');
    await tab(screen, 'ジャーナル');
    await expect(screen.getByText('今日のタスク')).toBeVisible();
    await app.screenshot(`journal-${appearance}`);
    await tab(screen, 'ライブラリ');
    await openLink(device, screen, 'memora://projects');
    await tap(screen, screen.getByRole('button', { name: 'ファイル', exact: true }).first());
    await expect(screen.getByRole('button', { name: 'ファイル', selected: true })).toBeVisible();
    await app.screenshot(`library-${appearance}`);
    await tab(screen, 'Ask AI');
    await expect(screen.getByLabel('新しいチャット')).toBeVisible();
    await app.screenshot(`ask-${appearance}`);
    await tap(screen, screen.getByLabel('メニュー'));
    await tap(screen, screen.getByRole('button', { name: '設定', exact: true }).last());
    await expect(screen.getByText('アカウント').first()).toBeVisible();
    await app.screenshot(`settings-${appearance}`);
  }
  await device.setAppearance('light');
});

test('design: mentions search, select twice, preserve focus, remove and use plus', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await openLink(device, screen, 'memora://ask-ai');
  const input = screen.getByTestId('ai.composer.input');
  await fillComposer(screen, '@file');
  const files = screen.getByRole('button', { name: 'ファイル・記録の検索、利用可能', exact: true });
  await expect(files).toBeVisible();
  await app.screenshot('mention-filtered');
  await tap(screen, files);
  await expect(input).toHaveValue(/\[@ファイル・記録の検索\]/);
  await expect(screen.getByRole('keyboard')).toBeVisible();
  await input.pressSequentially('@brief');
  await tap(screen, screen.getByRole('button', { name: 'プロジェクトの要点整理、利用可能', exact: true }));
  await expect(screen.getByLabel('プロジェクトの要点整理の指定を削除')).toBeVisible();
  await expect(screen.getByLabel('ファイル・記録の検索の指定を削除')).toBeVisible();
  await expect(screen.getByRole('keyboard')).toBeVisible();
  await tap(screen, screen.getByLabel('ファイル・記録の検索の指定を削除'));
  await expect(input).not.toHaveValue(/ファイル・記録の検索/);
  await tap(screen, screen.getByLabel('添付を追加'));
  await tap(screen, screen.getByText('プラグイン・スキル・ソース', { exact: true }));
  await expect(screen.getByLabel('候補を閉じる')).toBeVisible();
  await expect(screen.getByRole('keyboard')).toBeVisible();
  await input.fill('');
});

test('design: unavailable integrations explain their state', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await openLink(device, screen, 'memora://ask-ai');
  const input = screen.getByTestId('ai.composer.input');
  await fillComposer(screen, '@Drive');
  await expect(screen.getByRole('button', { name: 'Google Drive、利用不可', exact: true })).toBeVisible();
  await tap(screen, screen.getByRole('button', { name: 'Google Drive、利用不可', exact: true }));
  await expect(screen.getByText(/未接続|未対応|利用できません/).first()).toBeVisible();
});

test('design: project mentions preserve scope and the workspace three tabs', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await openLink(device, screen, 'memora://projects');
  await tap(screen, screen.getByRole('button', { name: 'プロジェクトを作成', exact: true }).first());
  await screen.getByPlaceholder('例：新規アプリ').fill(`E2E Scope ${Date.now()}`);
  await tap(screen, screen.getByRole('button', { name: '作成', exact: true }));
  for (const name of ['ファイル', 'ソース', 'チャット']) {
    await tap(screen, screen.getByRole('button', { name, exact: true }).first());
    await expect(screen.getByRole('button', { name, exact: true, selected: true })).toBeVisible();
  }
  const input = screen.getByTestId('ai.composer.input');
  await tap(screen, screen.getByRole('button', { name: 'ソース', exact: true }).first());
  await tap(screen, screen.getByLabel('ソースを追加').first());
  await screen.getByPlaceholder('タイトル').fill('ScopeEvidence');
  await tap(screen, screen.getByLabel('キーボードを閉じる'));
  await expect(screen.getByRole('keyboard')).not.toBeVisible();
  await scrollTo(screen, screen.getByLabel('メモ本文'));
  const body = screen.getByLabel('メモ本文');
  await tap(screen, body);
  await expect(body).toBeFocused();
  await body.fill('Offline source for scoped mention verification.');
  await tap(screen, screen.getByLabel('キーボードを閉じる'));
  await expect(screen.getByRole('keyboard')).not.toBeVisible();
  await scrollTo(screen, screen.getByRole('button', { name: 'メモを保存', exact: true }));
  await expect(screen.getByRole('button', { name: 'メモを保存', exact: true })).toBeEnabled();
  await tap(screen, screen.getByRole('button', { name: 'メモを保存', exact: true }));
  await expect(screen.getByLabel('メモ本文')).toHaveValue('');
  await tap(screen, screen.getByLabel('閉じる'));
  await fillComposer(screen, '@ScopeEvidence');
  await tap(screen, screen.getByRole('button', { name: 'ScopeEvidence、利用可能', exact: true }));
  await expect(screen.getByLabel('ScopeEvidenceの指定を削除')).toBeVisible();
  await app.screenshot('project-source-mention');
  await input.fill('');
  await fillComposer(screen, '@brief');
  await tap(screen, screen.getByRole('button', { name: 'プロジェクトの要点整理、利用可能', exact: true }));
  await expect(screen.getByLabel('プロジェクトの要点整理の指定を削除')).toBeVisible();
  await input.pressSequentially('@Notion');
  await expect(screen.getByRole('button', { name: 'Notion、利用不可', exact: true })).toBeVisible();
  await input.fill('@ScopeEvidence');
  await tap(screen, screen.getByRole('button', { name: 'ScopeEvidence、利用可能', exact: true }));
  await openLink(device, screen, 'memora://ask-ai');
  await expect(screen.getByLabel('ScopeEvidence、利用不可、情報を表示')).toBeVisible();
  await tap(screen, screen.getByRole('button', { name: '送信', exact: true }));
  await expect(screen.getByText(/このソースは所属プロジェクト内のAsk AI/)).toBeVisible();
  await tap(screen, screen.getByRole('button', { name: '閉じる', exact: true }).last());
  await expect(input).toHaveValue(/ScopeEvidence/);
  await input.fill('');
});

test('design: long Markdown edits use real SQLite persistence across restart', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await review(screen, device);
  await tap(screen, screen.getByText('検証データを片付ける'));
  await tap(screen, screen.getByText('検証用の要約を作成'));
  await tap(screen, screen.getByText('検証用の要約を開く'));
  const heading = screen.getByRole('button', { name: '次の一歩をそろえる', exact: true });
  await expect(heading).toBeVisible();
  await app.screenshot('summary-long-light');
  await device.setAppearance('dark');
  await app.screenshot('summary-long-dark');
  await tap(screen, heading);
  await expect(screen.getByRole('keyboard')).toBeVisible();
  await expect(screen.getByRole('textbox')).toBeFocused();
  await screen.getByRole('textbox').fill('E2E保存確認');
  await tap(screen, screen.getByRole('button', { name: '完了', exact: true }));
  await expect(screen.getByRole('button', { name: 'E2E保存確認', exact: true })).toBeVisible();
  await app.restart();
  await review(screen, device);
  await tap(screen, screen.getByText('SQLiteの保存を確認'));
  await expect(screen.getByText('SQLite再読込一致：編集内容を保存済み')).toBeVisible();
  await tap(screen, screen.getByText('検証用の要約を開く'));
  await expect(screen.getByRole('button', { name: 'E2E保存確認', exact: true })).toBeVisible();
  await tap(screen, screen.getByLabel('前に戻る'));
  await tap(screen, screen.getByText('検証データを片付ける'));
  await expect(screen.getByText('検証データを削除しました')).toBeVisible();
  await device.setAppearance('light');
});

test('design: conversation typography renders Japanese prose in both appearances', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await review(screen, device);
  await tap(screen, screen.getByTestId('BackButton'));
  await tap(screen, screen.getByText('OSSの部分移植（表示比較）'));
  await expect(screen.getByText('今週の方針', { exact: true })).toBeVisible();
  await expect(screen.getByText('読者が判断できる順番で、提案の構成と未確認事項を整理します。')).toBeVisible();
  await app.screenshot('conversation-fixture-light');
  await device.setAppearance('dark');
  await app.screenshot('conversation-fixture-dark');
  await device.setAppearance('light');
});
