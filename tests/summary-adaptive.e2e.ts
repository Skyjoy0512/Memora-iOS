import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { seedSummaryFixture } from './summary-fixture-helpers';
import { sql } from './sqlite-fixture-helpers';
import { scrollToControl, tapControl, tapTab, openSummaryPoster } from './ui-helpers';

test('content-led poster and meeting task creation preserve saved records', { timeout: 240_000, skip: 'The one-page summary poster is compiled off (FeatureFlags.isInlineSummaryPosterEnabled is false).' }, async ({ app, device, screen }) => {
  const summary = '## 選択肢の比較\n### 品質と制約\n| 案 | 利点 | 条件 |\n| --- | --- | --- |\n| A | 小さく試せる | 承認が必要 |\n## 次の実験\n- 同じデータで比較する\n  - 理由：条件の違いを避ける\n  - 条件：個人情報を除く';
  const { database, fixture, title } = await seedSummaryFixture(app, device, screen, {
    summary, raw: '架空のUI検証用です。', segmentID: '82828282-8282-4282-8282-828282828282', timestamp: 0,
  });
  const read = (key: string) => {
    const value = sql(database, `SELECT CAST(data AS TEXT) FROM documents WHERE key='${key}';`);
    return value ? JSON.parse(value) : [];
  };
  await expect(screen.getByTestId('summary.poster.inline')).toBeVisible();
  await openSummaryPoster(screen);
  await expect(screen.getByTestId('summary.poster.image')).toBeVisible();
  await app.screenshot('adaptive-poster-custom-headings');
  await tapControl(screen.getByRole('tab', { name: '全文', exact: true }));
  await expect(screen.getByText('選択肢の比較', { exact: true })).toBeVisible();
  await expect(screen.getByText('品質と制約', { exact: true })).toBeVisible();
  await tapControl(screen.getByRole('button', { name: '完了', exact: true }));
  const tasksSection = screen.getByRole('button', { name: '次にすること', exact: true });
  await scrollToControl(screen, tasksSection, { minimumY: 100, maximumY: 750 });
  await tapControl(tasksSection);
  const add = screen.getByTestId('meeting.tasks.add');
  await scrollToControl(screen, add, { minimumY: 100, maximumY: 750 });
  await expect(add).toHaveAccessibleName('タスクを追加');
  const box = await add.boundingBox();
  expect(box!.height).toBeGreaterThanOrEqual(44);
  expect(box!.width).toBeGreaterThanOrEqual(44);
  await app.screenshot('meeting-task-add-secondary-button');
  await tapControl(add);
  await expect(screen.getByRole('button', { name: '追加', exact: true })).toBeDisabled();
  const taskTitle = '同じデータで比較する・UI検証';
  await screen.getByRole('textbox', { name: 'すること', exact: true }).fill(taskTitle);
  await screen.getByRole('textbox', { name: 'メモ・完了条件', exact: true }).fill('個人情報を除く。自動実行しない。');
  await tapControl(screen.getByRole('button', { name: '追加', exact: true }));
  await expect.poll(() => read('memoraTasks').some((task: any) => task.title === taskTitle && task.meetingID.toLowerCase() === fixture.id.toLowerCase())).toBe(true);
  await expect(screen.getByRole('button', { name: taskTitle, exact: true })).toBeVisible();
  await app.restart();
  await tapTab(screen, 'ライブラリ');
  await tapControl(screen.getByRole('button', { name: new RegExp('^' + title) }).first());
  const task = screen.getByRole('button', { name: taskTitle, exact: true });
  await scrollToControl(screen, task, { minimumY: 100, maximumY: 750 });
  await tapControl(task);
  await expect(screen.getByRole('textbox', { name: 'タイトル', exact: true })).toHaveValue(taskTitle);
  await expect(screen.getByRole('textbox', { name: 'メモ・完了条件', exact: true })).toHaveValue('個人情報を除く。自動実行しない。');
  await tapControl(screen.getByRole('button', { name: 'キャンセル', exact: true }));
  expect(read('memoraMeetings')[0].summary).toBe(summary);
  expect(read('memoraMeetings')[0].transcript[0].text).toBe('架空のUI検証用です。');
});
