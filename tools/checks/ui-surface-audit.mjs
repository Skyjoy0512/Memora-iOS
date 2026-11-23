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

// The current tree has reviewed findings that are intentionally kept for a
// later pass. Only an exact file/rule/location match may stay quiet.
const acceptedBaseline = new Set([
  'App/AIChatModelSheet.swift:unreviewed-default-list',
  'App/CommunitySubmissionPicker.swift:unreviewed-default-list',
  'App/DocumentPDFExportExampleView.swift:unreviewed-default-list',
  'App/PresentationCatalogView.swift:unreviewed-default-list',
  'App/PresentationEditingExampleView.swift:unreviewed-default-list',
  'App/PresentationEditorView.swift:unreviewed-default-list',
  'App/ProjectNoteAttachSheet.swift:unreviewed-default-list',
  'App/TaskMeetingPicker.swift:unreviewed-default-list',
  'App/PhoneNumberEntryView.swift:emoji-in-string:19',
  'App/AIAnswerShareCard.swift:hue-gradient:54',
  'App/AIAnswerShareCard.swift:hue-gradient:55',
  'App/AvatarBackground.swift:hue-gradient:28',
  'App/AvatarBackground.swift:hue-gradient:38',
  'App/JournalBackdropView.swift:hue-gradient:18',
  'App/RootTabBackdrop.swift:hue-gradient:18',
  'App/ShimmerText.swift:hue-gradient:25',
  'App/AIAnswerShareCard.swift:radius-outside-scale:49',
  'App/AuthProviderButton.swift:radius-outside-scale:28',
  'App/CallIntroView.swift:radius-outside-scale:89',
  'App/CallIntroView.swift:radius-outside-scale:91',
  'App/CaptureMenuSheet.swift:radius-outside-scale:10',
  'App/DocumentPDFExportProgressView.swift:radius-outside-scale:26',
  'App/MarkdownBlockView.swift:radius-outside-scale:37',
  'App/MarketplaceArtwork.swift:radius-outside-scale:16',
  'App/MarketplaceArtwork.swift:radius-outside-scale:21',
  'App/MarketplaceItemIcon.swift:radius-outside-scale:17',
  'App/MarketplaceItemIcon.swift:radius-outside-scale:19',
  'App/MemoraSkeleton.swift:radius-outside-scale:7',
  'App/MemoraSkeleton.swift:radius-outside-scale:8',
  'App/MemoraSkeleton.swift:radius-outside-scale:9',
  'App/PhotoEditorView.swift:radius-outside-scale:94',
  'App/PhotoEditorView.swift:radius-outside-scale:95',
  'App/PixelLoader.swift:radius-outside-scale:56',
  'App/ProviderLogo.swift:radius-outside-scale:17',
  'App/ProviderLogo.swift:radius-outside-scale:20',
  'App/SidebarContainer.swift:radius-outside-scale:76',
  'App/AISettingsView.swift:sparkle-marker:51',
  'App/AISettingsView.swift:sparkle-marker:68',
  'App/DocumentsView.swift:sparkle-marker:53',
  'App/MailDraftsView.swift:sparkle-marker:32',
  'App/MeetingDetailView.swift:sparkle-marker:452',
  'App/MemoraInterfaceIcon.swift:sparkle-marker:58',
  'App/PersonDetailView.swift:sparkle-marker:59',
  'App/PrivacyStorageView.swift:sparkle-marker:36',
  'App/ProjectSourceDetailView.swift:sparkle-marker:206',
  'App/ResidentAgentsView.swift:sparkle-marker:41',
  'App/RootTabView.swift:sparkle-marker:367',
  'App/SearchView.swift:sparkle-marker:205',
  'App/SettingsCategoryView.swift:sparkle-marker:312',
  'App/SpaceDetailView.swift:sparkle-marker:92',
  'App/StateGalleryView.swift:sparkle-marker:132',
  'App/StateGalleryView.swift:sparkle-marker:181',
  'App/SummaryTemplateEditor.swift:sparkle-marker:69',
  'App/AIEngine.swift:sparkle-marker:37',
  'App/AIMessageView.swift:sparkle-marker:49',
  'App/CaptureAction.swift:sparkle-marker:41',
  'App/EditableMarkdownDocument.swift:radius-outside-scale:139',
  'App/MarkdownEditingToolbar.swift:radius-outside-scale:9',
  'App/MeetingStatus.swift:sparkle-marker:39',
  'App/MeetingStatus.swift:sparkle-marker:45',
  'App/ProjectSourceThumbnail.swift:radius-outside-scale:13',
  'App/SummaryTemplate.swift:sparkle-marker:42',
  'App/SummaryTemplateChoice.swift:sparkle-marker:49',
]);

const findings = [];
const addFinding = (file, rule, line) => {
  findings.push(line ? { file, line, rule } : { file, rule });
};
const findingKey = finding => `${finding.file}:${finding.rule}${finding.line ? `:${finding.line}` : ''}`;

// Sweep Swift source in one pass. Code lines lose comments and string literals
// so prose cannot look like an API call; string lines retain only literal
// contents so an emoji in a comment or identifier does not count.
function scanSwift(text) {
  const codeLines = [''];
  const stringLines = [''];
  let line = 0;
  let inString = false;
  let stringKind = 'single';
  let rawHashes = 0;
  let interpolationDepth = 0;
  let inLineComment = false;
  let blockDepth = 0;

  const appendCode = value => { codeLines[line] += value; };
  const appendString = value => { stringLines[line] += value; };
  const newline = () => {
    codeLines[line] += '\n';
    stringLines[line] += '\n';
    line += 1;
    codeLines[line] = '';
    stringLines[line] = '';
    inLineComment = false;
  };
  const mask = count => appendCode(' '.repeat(count));

  let index = 0;
  while (index < text.length) {
    const char = text[index];

    if (char === '\n') {
      newline();
      index += 1;
      continue;
    }

    if (inLineComment) {
      mask(1);
      index += 1;
      continue;
    }

    if (blockDepth > 0) {
      if (char === '/' && text[index + 1] === '*') {
        blockDepth += 1;
        mask(2);
        index += 2;
      } else if (char === '*' && text[index + 1] === '/') {
        blockDepth -= 1;
        mask(2);
        index += 2;
      } else {
        mask(1);
        index += 1;
      }
      continue;
    }

    if (interpolationDepth > 0) {
      if (char === '(') {
        interpolationDepth += 1;
      } else if (char === ')') {
        interpolationDepth -= 1;
      }
      appendString(char);
      mask(1);
      index += 1;
      continue;
    }

    if (inString) {
      const closing = stringKind === 'single'
        ? `"${'#'.repeat(rawHashes)}`
        : `"""${'#'.repeat(rawHashes)}`;
      if (text.startsWith(closing, index)) {
        mask(closing.length);
        index += closing.length;
        inString = false;
        interpolationDepth = 0;
        continue;
      }
      if (rawHashes === 0 && char === '\\' && text[index + 1] === '(') {
        appendString('\\(');
        mask(2);
        index += 2;
        interpolationDepth = 1;
        continue;
      }
      if (rawHashes === 0 && char === '\\' && index + 1 < text.length) {
        appendString(char);
        mask(1);
        index += 1;
        if (text[index] === '\n') {
          newline();
        } else {
          appendString(text[index]);
          mask(1);
        }
        index += 1;
        continue;
      }
      appendString(char);
      mask(1);
      index += 1;
      continue;
    }

    if (char === '/' && text[index + 1] === '/') {
      inLineComment = true;
      mask(2);
      index += 2;
      continue;
    }

    if (char === '/' && text[index + 1] === '*') {
      blockDepth = 1;
      mask(2);
      index += 2;
      continue;
    }

    if (char === '#') {
      let hashes = 0;
      while (text[index + hashes] === '#') hashes += 1;
      if (text[index + hashes] === '"') {
        if (text.startsWith('"""', index + hashes)) {
          rawHashes = hashes;
          stringKind = 'multi';
          mask(hashes + 3);
          index += hashes + 3;
        } else {
          rawHashes = hashes;
          stringKind = 'single';
          mask(hashes + 1);
          index += hashes + 1;
        }
        inString = true;
        continue;
      }
    }

    if (char === '"') {
      rawHashes = 0;
      if (text.startsWith('"""', index)) {
        stringKind = 'multi';
        mask(3);
        index += 3;
      } else {
        stringKind = 'single';
        mask(1);
        index += 1;
      }
      inString = true;
      continue;
    }

    appendCode(char);
    index += 1;
  }

  return { codeLines, stringLines };
}

const gradientPattern = /\b(?:LinearGradient|RadialGradient|MeshGradient)\b/;
const sparklePattern = /\.sparkles\b/;
const emojiPattern = /\p{Emoji_Presentation}|\p{Extended_Pictographic}\uFE0F/u;
const allowedRadii = new Set([8, 12, 16, 24]);
const numberPattern = /(?<![\w.])\d+(?:\.\d+)?(?![\w.])/g;

function cornerRadiusText(code, start) {
  let index = start;
  while (index < code.length && /\s/.test(code[index])) index += 1;
  if (code[index] === ':' || code[index] === '=') index += 1;
  while (index < code.length && /\s/.test(code[index])) index += 1;
  if (code[index] === '(') index += 1;

  let depth = 0;
  let value = '';
  for (; index < code.length; index += 1) {
    const char = code[index];
    if (char === '(' || char === '[' || char === '{') {
      depth += 1;
    } else if (char === ')' || char === ']' || char === '}') {
      if (depth === 0) break;
      depth -= 1;
    } else if (char === ',' && depth === 0) {
      break;
    }
    value += char;
  }
  return value;
}

for (const file of views) {
  const lines = file.text.split('\n');
  lines.forEach((line, index) => {
    if (line.includes('.background(Color(uiColor: .systemGroupedBackground))')) {
      addFinding(file.path, 'grouped-page-canvas', index + 1);
    }
    if (line.includes('.foregroundStyle(.white)') &&
        lines.slice(index + 1, index + 7).some(next => /\.background\(\.tint[,)]/.test(next))) {
      addFinding(file.path, 'white-on-adaptive-tint', index + 1);
    }
  });
  if (/\bList\s*\{/.test(file.text) && !inheritedLists.has(file.path) &&
      !/\.listStyle\(\.plain\)|\.memoraPlainList\(\)|\.memoraSettingsPage\(/.test(file.text)) {
    addFinding(file.path, 'unreviewed-default-list');
  }
}

for (const file of files) {
  const { codeLines, stringLines } = scanSwift(file.text);
  const seen = new Set();

  codeLines.forEach((code, index) => {
    const line = index + 1;

    if (gradientPattern.test(code) && file.path !== 'App/MarketplaceArtwork.swift') {
      const key = `hue-gradient:${line}`;
      if (!seen.has(key)) {
        seen.add(key);
        addFinding(file.path, 'hue-gradient', line);
      }
    }

    let radiusOutsideScale = false;
    const radiusPattern = /cornerRadius\b/g;
    let match;
    while ((match = radiusPattern.exec(code)) !== null) {
      const expression = cornerRadiusText(code, radiusPattern.lastIndex);
      for (const value of expression.match(numberPattern) ?? []) {
        if (!allowedRadii.has(Number(value))) {
          radiusOutsideScale = true;
          break;
        }
      }
      if (radiusOutsideScale) break;
    }
    if (radiusOutsideScale) {
      const key = `radius-outside-scale:${line}`;
      if (!seen.has(key)) {
        seen.add(key);
        addFinding(file.path, 'radius-outside-scale', line);
      }
    }

    if (sparklePattern.test(code)) {
      const key = `sparkle-marker:${line}`;
      if (!seen.has(key)) {
        seen.add(key);
        addFinding(file.path, 'sparkle-marker', line);
      }
    }
  });

  stringLines.forEach((literal, index) => {
    const line = index + 1;
    if (emojiPattern.test(literal)) {
      const key = `emoji-in-string:${line}`;
      if (!seen.has(key)) {
        seen.add(key);
        addFinding(file.path, 'emoji-in-string', line);
      }
    }
  });
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
process.exitCode = findings.some(finding => !acceptedBaseline.has(findingKey(finding))) ? 1 : 0;
