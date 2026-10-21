import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// This is a source sweep, not a claim of visual or device validation.
const app = fileURLToPath(new URL('../../App/', import.meta.url));
const files = fs.readdirSync(app, { recursive: true })
  .filter(file => file.endsWith('.swift'))
  .map(file => ({ path: `App/${file}`, text: fs.readFileSync(path.join(app, file), 'utf8') }));
const views = files.filter(file => /\bstruct\s+\w+[^\n]*:\s*(?:View|UIViewRepresentable|UIViewControllerRepresentable)\b/.test(file.text));
const inheritedLists = new Set([
  'App/ToolsSkillsList.swift', 'App/ToolsTemplatesList.swift', 'App/ToolsConnectorsList.swift',
  'App/MemoraList.swift',
]);
const findings = [];
for (const file of views) {
  const lines = file.text.split('\n');
  lines.forEach((line, index) => {
    if (line.includes('.background(Color(uiColor: .systemGroupedBackground))')) {
      findings.push({ file: file.path, line: index + 1, rule: 'grouped-page-canvas' });
    }
    if (line.includes('.foregroundStyle(.white)') &&
        lines.slice(index + 1, index + 7).some(next => /\.background\(\.tint[,)]/.test(next))) {
      findings.push({ file: file.path, line: index + 1, rule: 'white-on-adaptive-tint' });
    }
  });
  if (/\bList\s*\{/.test(file.text) && !inheritedLists.has(file.path) &&
      !/\.listStyle\(\.plain\)|\.memoraPlainList\(\)|\.memoraSettingsPage\(/.test(file.text)) {
    findings.push({ file: file.path, rule: 'unreviewed-default-list' });
  }
}
const inventory = views.map(file => ({
  file: file.path,
  screenCandidate: /(?:View|Sheet|Editor)\.swift$/.test(file.path),
  nativeMedia: /import (?:PDFKit|PhotosUI|MapKit|QuickLook)/.test(file.text),
  containers: [...new Set(file.text.match(/\b(?:MemoraForm|MemoraList|List|ScrollView|TabView|NavigationStack)\b/g) ?? [])],
  titleCount: (file.text.match(/\.navigationTitle\(/g) ?? []).length,
}));
console.log(JSON.stringify({
  sourceFiles: files.length,
  viewFiles: views.length,
  screenCandidates: inventory.filter(file => file.screenCandidate).length,
  findings,
  ...(process.argv.includes('--inventory') ? { inventory } : {}),
}, null, 2));
process.exitCode = findings.length ? 1 : 0;
