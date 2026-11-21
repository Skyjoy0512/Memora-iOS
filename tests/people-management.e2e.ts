import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, tapControl } from './ui-helpers';

test('removing a person confirms what happens to related records and can be cancelled', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapControl(screen.getByLabel('メニュー').first());
  await tapControl(screen.getByRole('button', { name: '人物', exact: true }));
  await tapControl(screen.getByRole('button', { name: '人を追加', exact: true }));
  const name = '確認用の人物';
  await screen.getByPlaceholder('名前').fill(name);
  await tapControl(screen.getByRole('button', { name: '追加', exact: true }));
  const person = screen.getByRole('button', { name: `${name}を編集`, exact: true });

  async function requestDeletion() {
    await expect(person).toBeVisible();
    const box = await person.boundingBox();
    if (!box) throw new Error('Missing person row');
    const centerY = box.y + box.height / 2;
    await screen.swipe({ from: { x: box.x + box.width - 8, y: centerY }, to: { x: box.x + 8, y: centerY }, duration: 400 });
    await tapControl(screen.getByRole('button', { name: '削除', exact: true }));
    await expect(screen.getByText('この人物を削除しますか？', { exact: true })).toBeVisible();
    await expect(screen.getByText(/記録・タスク・ジャーナルの内容は残ります/)).toBeVisible();
  }

  await requestDeletion();
  await tapControl(screen.getByRole('button', { name: 'キャンセル', exact: true }));
  await expect(person).toBeVisible();
  await requestDeletion();
  await tapControl(screen.getByRole('button', { name: '削除', exact: true }));
  await expect(person).not.toBeVisible();
});
