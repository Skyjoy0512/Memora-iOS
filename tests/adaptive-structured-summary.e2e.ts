import { createHash, randomUUID } from 'node:crypto';
import { afterEach, test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { seedSummaryFixture } from './summary-fixture-helpers';
import { readMeetings, sql, writeMeetings } from './sqlite-fixture-helpers';
import { scrollToControl, tapControl, tapTab, replaceEditorWithPaste, restartToLibrary } from './ui-helpers';

afterEach(async ({ device }) => { await device.setAppearance('light'); });

// Only the UI-identified dedicated simulator is seeded. No model calls,
// microphone, credentials or external writes are involved.
test('adaptive reading retains task operations, facts and transcript evidence', { timeout: 420_000 }, async ({ app, device, screen }) => {
  const raw = '負荷試験で問題が見つかったため、11月20日の公開予定を再検討します。担当者は次回決めます。';
  const body = '負荷試験の問題を確認したため、当初の11月20日公開を再検討する。';
  const summary = '# 公開時期の再検討\n\n' + body + '\n\n## 検証と公開の条件\n- 承認後に判断する\n\n## 案の比較\n| 案 | 利点 | 条件 |\n| --- | --- | --- |\n| 段階公開 | 小さく試せる | 承認後 |\n| 全体公開 | 一度に切り替え | 負荷試験後 |';
  const { database, fixture, title } = await seedSummaryFixture(app, device, screen, {
    summary, raw, segmentID: randomUUID(), timestamp: 12,
  });
  const read = (key: string) => key === 'memoraMeetings'
    ? readMeetings(database) ?? []
    : JSON.parse(sql(database, `SELECT CAST(data AS TEXT) FROM documents WHERE key='${key}';`) || '[]');
  await device.closeApp();
  // This is the real TranscriptSegment codec's sorted-keys representation.
  const segment = { id: fixture.transcript[0].id.toUpperCase(), identificationStatus: 'manual', speaker: '話者1', speakerIsCertain: true, text: raw, timestamp: 12 };
  const sourceFingerprint = createHash('sha256').update(JSON.stringify([segment])).digest('hex');
  const versionID = randomUUID();
  const version = { id: versionID, sourceRecordID: fixture.id, templateID: 'market.releaseReview', summaryLength: 'standard', displayOrder: 'importance',
    sections: [], generatedAt: fixture.createdAt, modelInfo: '明示的なUI fixture', schemaVersion: 3, markdown: summary,
    keyPoints: [], decisions: [], openQuestions: [], sourceFingerprint,
    knowledge: { schemaVersion: 1, selectedProfileIDs: ['market.releaseReview'], contentType: 'meeting', topics: [{ id: 't1', title: '公開時期の再検討' }],
      facts: [{ id: 'f1', category: 'decision', content: '公開時期を再検討する', status: 'confirmed', relatedTopicID: 't1',
        sourceReferences: [{ sourceSegmentID: segment.id, quote: '11月20日の公開予定を再検討します' }] }],
      coverage: [{ aspect: '担当の確定', status: 'pending' }, { aspect: '予算', status: 'notMentioned' }] } };
  writeMeetings(database, [{ ...fixture, summaryVersions: [version], activeSummaryVersionID: versionID }]);
  await restartToLibrary(app, screen);
  await tapControl(screen.getByRole('button', { name: new RegExp('^' + title) }).first());
  await expect(screen.getByTestId('ai.composer.input')).toBeVisible();
  await expect(screen.getByRole('button', { name: '追加メニュー', exact: true })).not.toBeVisible();
  await expect(screen.getByRole('button', { name: body, exact: true })).toBeVisible();
  await expect(screen.getByText('予算', { exact: true })).not.toBeVisible();
  await app.screenshot('adaptive-short-light');
  await device.setAppearance('dark');
  await app.screenshot('adaptive-short-dark');
  await tapControl(screen.getByRole('button', { name: 'その他', exact: true }));
  await tapControl(screen.getByTestId('meeting.summary.extraction'));
  await expect(screen.getByTestId('summary.extraction.stale')).not.toBeVisible();
  await scrollToControl(screen, screen.getByText('公開時期を再検討する', { exact: true }));
  await expect(screen.getByText('公開時期を再検討する', { exact: true })).toBeVisible();
  await app.screenshot('adaptive-extracted-facts-dark');
  const evidence = screen.getByRole('button', { name: '原文を確認 00:12', exact: true });
  await scrollToControl(screen, evidence);
  await tapControl(evidence);
  await expect(screen.getByRole('button', { name: raw, exact: true })).toBeVisible();
  await expect(screen.getByRole('button', { name: '文字起こし', exact: true })).toBeSelected();
  await app.screenshot('adaptive-evidence-without-audio');
  await tapControl(screen.getByRole('button', { name: '要約', exact: true }));
  await tapControl(screen.getByRole('button', { name: 'その他', exact: true }));
  await tapControl(screen.getByTestId('meeting.summary.extraction'));
  const add = screen.getByTestId('meeting.tasks.add');
  await scrollToControl(screen, add);
  await tapControl(add);
  const taskTitle = '原文を確認する・適応型UI検証';
  await screen.getByRole('textbox', { name: 'すること', exact: true }).fill(taskTitle);
  await tapControl(screen.getByRole('button', { name: '追加', exact: true }));
  await expect.poll(() => read('memoraTasks').some((task: any) => task.title === taskTitle)).toBe(true);
  const complete = screen.getByRole('button', { name: taskTitle + 'を完了にする', exact: true });
  await scrollToControl(screen, complete);
  await tapControl(complete);
  await expect.poll(() => read('memoraTasks').find((task: any) => task.title === taskTitle)?.isCompleted).toBe(true);
  expect(read('memoraMeetings')[0].summary).toBe(summary);
  expect(read('memoraMeetings')[0].transcript[0].text).toBe(raw);
  await app.screenshot('adaptive-task-completed');
  const editFact = screen.getByTestId('summary.fact.edit.f1');
  await scrollToControl(screen, editFact);
  await tapControl(editFact);
  await screen.getByTestId('summary.fact.content').fill('公開日は本人が別途確認する');
  await tapControl(screen.getByTestId('summary.fact.save'));
  await expect.poll(() => read('memoraMeetings')[0].summaryVersions.length).toBe(2);
  const edited = read('memoraMeetings')[0];
  expect(edited.summary).toBe(summary);
  expect(edited.summaryVersions[0].knowledge.facts[0].content).toBe('公開時期を再検討する');
  expect(edited.summaryVersions[1].knowledge.facts[0].origin).toBe('user');
  expect(edited.summaryVersions[1].knowledge.facts[0].sourceReferences).toEqual([]);
  await scrollToControl(screen, screen.getByTestId('summary.extraction.stale'));
  await expect(screen.getByTestId('summary.extraction.stale')).toBeVisible();
  await app.screenshot('adaptive-authored-extraction-keeps-history');
  await tapControl(screen.getByRole('button', { name: '完了', exact: true }));
  await tapControl(screen.getByRole('button', { name: 'その他', exact: true }));
  await tapControl(screen.getByRole('button', { name: '要約をコピー', exact: true }));
  expect(await device.clipboard()).toBe(summary);
  await tapControl(screen.getByRole('button', { name: '共有', exact: true }));
  await expect(screen.getByRole('listitem', { name: /^(Copy|コピー)$/ }).first()).toBeVisible();
  await app.screenshot('adaptive-native-share');
  await tapControl(screen.getByRole('button', { name: /^(Close|閉じる)$/ }).first());
  // The system share sheet can leave the app's tree detached; come back through
  // the app's own Library instead of assuming the detail returned.
  await restartToLibrary(app, screen);
  await tapControl(screen.getByRole('button', { name: new RegExp('^' + title) }).first());
  await tapControl(screen.getByRole('button', { name: 'その他', exact: true }));
  await tapControl(screen.getByTestId('meeting.summary.regenerate'));
  await expect(screen.getByTestId('summary.engineChoice')).toBeVisible();
  await tapControl(screen.getByRole('button', { name: 'キャンセル', exact: true }));
  expect(read('memoraMeetings')[0].summary).toBe(summary);
  await tapControl(screen.getByRole('button', { name: 'その他', exact: true }));
  await tapControl(screen.getByRole('button', { name: '要約の履歴', exact: true }));
  await expect(screen.getByRole('button', { name: /本人による抽出情報の編集/ })).toBeVisible();
  await tapControl(screen.getByRole('button', { name: /明示的なUI fixture/ }));
  await scrollToControl(screen, screen.getByRole('button', { name: 'この要約を復元', exact: true }));
  await tapControl(screen.getByRole('button', { name: 'この要約を復元', exact: true }));
  await tapControl(screen.getByRole('button', { name: '復元', exact: true }));
  await expect.poll(() => read('memoraMeetings')[0].activeSummaryVersionID.toLowerCase()).toBe(versionID.toLowerCase());
  expect(read('memoraTasks').find((task: any) => task.title === taskTitle)?.isCompleted).toBe(true);
  expect(read('memoraMeetings')[0].summaryVersions).toHaveLength(2);
  await app.screenshot('adaptive-history-restores-without-task-rollback');
  await device.back();
  await device.back();
  const tableCell = screen.getByRole('button', { name: '段階公開', exact: true });
  await scrollToControl(screen, tableCell);
  await tapControl(tableCell);
  const cellEditor = screen.getByRole('textbox', { name: '本文', exact: true });
  await expect(cellEditor).toHaveValue('段階公開');
  await tapControl(cellEditor);
  await expect.poll(async () => {
    const field = await cellEditor.boundingBox();
    const done = await screen.getByRole('button', { name: '完了', exact: true }).boundingBox();
    return !!field && !!done && field.y + field.height <= done.y;
  }).toBe(true);
  await app.screenshot('adaptive-table-editor-above-keyboard');
  await replaceEditorWithPaste(screen, device, cellEditor, '限定公開');
  await expect(cellEditor).toHaveValue('限定公開');
  await tapControl(screen.getByRole('button', { name: '完了', exact: true }));
  await expect.poll(() => read('memoraMeetings')[0].summary).toBe(summary.replace('| 段階公開 |', '| 限定公開 |'));
  expect(read('memoraMeetings')[0].transcript[0].text).toBe(raw);
  expect(read('memoraTasks').find((task: any) => task.title === taskTitle)?.isCompleted).toBe(true);
  await app.screenshot('adaptive-table-inline-edit');

});
