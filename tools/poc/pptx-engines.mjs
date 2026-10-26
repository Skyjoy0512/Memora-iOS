// Development-only PoC. Install pinned engines outside the app checkout first:
// npm install --prefix <scratch> --ignore-scripts --save-exact pptxgenjs@4.0.1 @office-kit/pptx@0.28.0
// node tools/poc/pptx-engines.mjs <scratch>/node_modules <new-output-directory>
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const [modules, destination] = process.argv.slice(2).map(p => resolve(p));
if (!modules || !destination) throw new Error('Pass module directory and new output directory');
await mkdir(destination); // Never overwrite an earlier run or an original company file.
const require = createRequire(join(modules, '_probe.cjs'));
const PptxGenJS = require('pptxgenjs');
const kit = await import(pathToFileURL(join(modules, '@office-kit/pptx/dist/index.js')));
const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const photo = join(root, 'App/Assets.xcassets/journal-leaves.imageset/photo.jpg');
const replacement = join(root, 'App/Assets.xcassets/journal-lake.imageset/photo.jpg');
const deck = new PptxGenJS();
deck.layout = 'LAYOUT_WIDE';
deck.author = 'Memora engine evaluation';
deck.subject = 'Synthetic local fixtures; not business evidence';
deck.title = 'Memora・編集可能な資料の検証';
deck.lang = 'ja-JP';
deck.theme = { headFontFace: 'Hiragino Sans', bodyFontFace: 'Hiragino Sans', lang: 'ja-JP' };
deck.defineSlideMaster({ title: 'MEMORA', background: { color: 'FFFFFF' }, objects: [
  { text: { text: 'Memora / 表示検証用・架空の数値', options: { x: 0.6, y: 7.05, w: 10, h: 0.2, fontSize: 9, color: '666666' } } },
] });
const box = { fontFace: 'Hiragino Sans', color: '171717', margin: 0, breakLine: false };
function slide(title) {
  const result = deck.addSlide('MEMORA');
  result.addText(title, { ...box, x: 0.65, y: 0.5, w: 12, h: 0.7, fontSize: 28, bold: true });
  result.addNotes('発表者ノート：表示・編集の検証用。数値と社名はすべて架空です。');
  return result;
}
let s = slide('{{company}} の四半期報告');
s.addText('結論：導入範囲を限定し、品質を確認して拡大する。', { ...box, x: 0.7, y: 2.5, w: 11.9, h: 1.2, fontSize: 30 });
s = slide('比較：価格だけでなく、保守負荷で選ぶ');
s.addTable([['方式', '現在の状態', '判断'], ['iOS内の生成', 'オフラインで利用可能', '継続'], ['Node生成', '開発環境のPoC', '本番は未導入'], ['常駐クラウド', '固定費が必要', '今回対象外']], {
  x: 0.7, y: 1.7, w: 11.9, h: 3.4, fontFace: 'Hiragino Sans', fontSize: 18,
  border: { type: 'solid', pt: 0.5, color: 'CCCCCC' }, color: '171717', fill: 'FFFFFF', margin: 0.16,
  rowH: 0.7, bold: false,
});
s = slide('Before / After');
for (const [x, title, text] of [[0.7, 'Before', '箇条書きだけの均一な資料'], [6.9, 'After', '構造・図表・ノートを保持する編集可能な資料']]) {
  s.addText(title, { ...box, x, y: 1.8, w: 5.6, h: 0.5, fontSize: 22, bold: true });
  s.addText(text, { ...box, x, y: 2.6, w: 5.6, h: 1.6, fontSize: 24 });
}
for (const [kind, title] of [[deck.ChartType.bar, '棒グラフ'], [deck.ChartType.line, '折れ線グラフ'], [deck.ChartType.pie, '円グラフ']]) {
  s = slide(`${title}：架空の検証データ`);
  s.addChart(kind, [{ name: '検証値', labels: ['4月', '5月', '6月'], values: [20, 35, 45] }], {
    x: 1, y: 1.7, w: 11, h: 4.5, showLegend: false, showValue: true, showTitle: false,
    chartColors: ['222222', '777777', 'BBBBBB'], showBorder: false, catAxisLabelFontFace: 'Hiragino Sans',
    showCatName: kind === deck.ChartType.pie, catAxisLabelFontSize: 16, valAxisLabelFontSize: 14,
  });
}
s = slide('プロセス：確認してから反映する');
['生成', '検証', '保存'].forEach((text, index) => {
  s.addShape(deck.ShapeType.rect, { x: 0.9 + index * 4.2, y: 2.6, w: 3, h: 1.2, fill: { color: 'F2F2F2' }, line: { color: 'CCCCCC' } });
  s.addText(text, { ...box, x: 0.9 + index * 4.2, y: 2.9, w: 3, h: 0.5, align: 'center', fontSize: 24 });
  if (index < 2) s.addShape(deck.ShapeType.line, { x: 3.95 + index * 4.2, y: 3.2, w: 1.05, h: 0, line: { color: '222222', endArrowType: 'triangle' } });
});
s = slide('画像：縦横比を保つ');
s.addImage({ path: photo, x: 1, y: 1.6, w: 11.2, h: 4.9,
  sizing: { type: 'contain', x: 1, y: 1.6, w: 11.2, h: 4.9 } });
const original = join(destination, 'pptxgenjs.pptx');
const started = performance.now();
await deck.writeFile({ fileName: original });
const generatedMS = performance.now() - started;
const originalBytes = await readFile(original);
const pres = await kit.loadPresentation(originalBytes);
assert.equal(kit.getSlides(pres).length, 8);
const replacements = kit.replaceTokensInPresentation(pres, { company: 'Memora 検証会社' });
assert.ok(replacements > 0);
const duplicate = kit.duplicateSlide(pres, kit.getSlides(pres)[2]);
const heading = kit.getSlideShapes(duplicate).find(shape => kit.getShapeText(shape).includes('Before / After'));
assert.ok(heading);
kit.setShapeText(heading, '複製して編集：日本語の見出し');
kit.setSlideNotes(duplicate, '変更後のノート。元の会社PPTXは変更しない。');
const picture = kit.getSlideShapes(kit.getSlides(pres)[7]).find(shape => kit.getShapeImageBytes(shape));
assert.ok(picture);
kit.setShapeImage(picture, await readFile(replacement), { format: 'jpeg', fit: 'contain' });
const chart = kit.getSlideCharts(kit.getSlides(pres)[3])[0];
assert.ok(chart);
kit.setChartData(chart, { categories: ['4月', '5月', '6月'], series: [{ name: '検証値', values: [22, 36, 48] }] });
const edited = await kit.savePresentation(pres);
await writeFile(join(destination, 'office-kit-edited.pptx'), edited);
const reloaded = await kit.loadPresentation(edited);
assert.equal(kit.getSlides(reloaded).length, 9);
assert.ok(kit.getSlideNotes(kit.getSlides(reloaded).at(-1)).includes('変更後のノート'));
assert.deepEqual(kit.getShapeChartSeriesValues(kit.getSlideCharts(kit.getSlides(reloaded)[3])[0].shape, '検証値'), [22, 36, 48]);
assert.deepEqual(await readFile(original), originalBytes);
const result = { platform: process.platform, architecture: process.arch, node: process.version,
  pptxgenjs: deck.version, officeKit: '0.28.0',
  sourceSlides: 8, editedSlides: 9, generatedMS, tokenReplacements: replacements,
  passed: ['native text', 'native table', 'bar/line/pie charts', 'shapes/connectors', 'image containment',
    'theme/master', 'Japanese strings', 'speaker notes', 'load/edit/duplicate/reload', 'chart data update', 'original bytes unchanged'],
  notProven: ['corporate template fidelity', 'Japanese font fidelity', 'Microsoft PowerPoint rendering', 'Workers runtime compatibility'] };
await writeFile(join(destination, 'result.json'), JSON.stringify(result, null, 2) + '\n');
console.log(JSON.stringify(result));
