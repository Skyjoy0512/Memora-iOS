import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
const tools = new Set(JSON.parse(readFileSync(new URL('./allowed-tools.json', import.meta.url))));
export class APIError extends Error { constructor(status, message) { super(message); this.status = status; } }
const fail = () => { throw new APIError(400, '共有する内容を確認してください。'); };
function text(value, max, required = false) {
  if (typeof value !== 'string' || value.length > max || (required && !value.trim())) fail();
  return value;
}
function list(value, max, length) {
  if (!Array.isArray(value) || value.length > max) fail();
  return value.map(v => { const result = text(v, length, true); if (/[\r\n]/.test(result)) fail(); return result; });
}
export function definition(input) {
  if (!input || Buffer.byteLength(JSON.stringify(input)) > 32768 || input.version !== 1) fail();
  if (input.kind === 'skill') {
    const s = input.skill;
    if (!s || /[\r\n]/.test(s.name + s.summary)) fail();
    const names = list(s.declaredToolNames ?? [], 16, 128);
    if (new Set(names).size !== names.length || names.some(t => !tools.has(t))) fail();
    const scopes = list(s.scopes ?? ['global'], 4, 16);
    if (scopes.some(s => !['global','project','record','person'].includes(s))) fail();
    const cost = s.cost ?? '料金未確認';
    if (!['選択中のAIの料金','外部処理は承認時に確認','料金未確認'].includes(cost)) fail();
    const extra = {};
    if (s.category !== undefined) {
      if (!['work','learning','writing','creative','life','custom'].includes(s.category)) fail();
      extra.category = s.category;
    }
    if (s.examplePrompts !== undefined) extra.examplePrompts = list(s.examplePrompts,3,300);
    if (s.outputDescription !== undefined) {
      extra.outputDescription = text(s.outputDescription,240,true);
      if (/[\r\n]/.test(extra.outputDescription)) fail();
    }
    return {version:1,kind:'skill',skill:{id:'custom-00000000-0000-4000-8000-000000000000',
      name:text(s.name,80,true),summary:text(s.summary,400,true),instructions:text(s.instructions,6000,true),
      keywords:list(s.keywords ?? [],8,40),declaredToolNames:names,
      declaredPermissions:list(s.declaredPermissions ?? [],8,120),version:1,
      iconIdentifier:text(s.iconIdentifier ?? 'doc.richtext',80),scopes,cost,...extra}};
  }
  if (input.kind === 'template') {
    const t = input.template;
    if (!t || /[\r\n]/.test(t.title) || !['meetings','customers','people','projects','learning','care','field','life'].includes(t.category)) fail();
    const sections = list(t.sections ?? [],12,80), prompt = text(t.prompt ?? '',6000);
    if ((!sections.length && !prompt.trim()) || new Set(sections).size !== sections.length) fail();
    return {version:1,kind:'template',template:{id:'custom.shared',title:text(t.title,80,true),
      detail:text(t.detail,400),symbol:text(t.symbol ?? 'doc.text',80),lead:text(t.title,80,true),category:t.category,
      sections,focus:text(t.focus ?? '',3000),prompt,includesActions:t.includesActions === true,isCustom:true,
      occupationTags:[],useCaseTags:[],defaultDisplayOrder:0,
      sensitivityClassification:['general','personal','sensitive'].includes(t.sensitivityClassification) ? t.sensitivityClassification : 'general',
      supportedSummaryLengths:['concise','standard','detailed']}};
  }
  fail();
}
export function metadata(value) {
  return value.kind === 'skill' ? {title:value.skill.name,summary:value.skill.summary} : {title:value.template.title,summary:value.template.detail};
}
export function versionID(value) { return createHash('sha256').update(JSON.stringify(value)).digest('hex'); }
export function identifier(value) { if (typeof value !== 'string' || !/^[a-zA-Z0-9_-]{1,128}$/.test(value)) fail(); return value; }
export function authorName(value) { const name = text(value,60,true).trim(); if (/[\r\n]/.test(name)) fail(); return name; }
