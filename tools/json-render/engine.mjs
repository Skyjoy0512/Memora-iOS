import { createSpecStreamCompiler, validateSpec, deepMergeSpec, diffToPatches, applySpecPatch, nestedToFlat, createStateStore } from '@json-render/core';
import { createYamlStreamCompiler } from '@json-render/yaml';
import { applyPatch as applyUnifiedDiff } from 'diff';
import { stringify as stringifyYAML, parse as parseYAML } from 'yaml';
import { definitions, actionDefinitions, builtInActions } from './catalog.mjs';

export const limits = {bytes:262144,stateBytes:65536,elements:256,depth:24,array:200,nodes:12000};
const forbidden = new Set(['__proto__','constructor','prototype']);
const encoder = new TextEncoder();
export function safeValue(value, maxBytes=limits.bytes) {
  if (encoder.encode(JSON.stringify(value)).length > maxBytes) throw Error('size');
  let nodes=0;
  function visit(value,depth) {
    if (++nodes>limits.nodes || depth>limits.depth) throw Error('depth');
    if (typeof value==='number' && !Number.isFinite(value)) throw Error('number');
    if (Array.isArray(value)) {
      if (value.length>limits.array) throw Error('array');
      value.forEach(child=>visit(child,depth+1));
    } else if (value && typeof value==='object') {
      for (const [key,child] of Object.entries(value)) {
        if (forbidden.has(key)) throw Error('key');
        visit(child,depth+1);
      }
    } else if (typeof value==='string' && value.length>32768) throw Error('string');
  }
  visit(value,0); return value;
}
export function safePath(path) {
  if (typeof path!=='string' || path.length>512 || (path!=='' && !path.startsWith('/'))) throw Error('path');
  for (const part of path.split('/')) if (forbidden.has(part.replaceAll('~1','/').replaceAll('~0','~'))) throw Error('path');
  return path;
}
export function checkPatch(patch) {
  safeValue(patch);
  if (!['add','replace','remove','move','copy','test'].includes(patch.op)) throw Error('operation');
  safePath(patch.path);
  if (patch.from!==undefined) safePath(patch.from);
  if (['add','replace','test'].includes(patch.op) && !Object.hasOwn(patch,'value')) throw Error('value');
  if (['move','copy'].includes(patch.op) && typeof patch.from!=='string') throw Error('from');
  return patch;
}
function checkActions(value) {
  if (Array.isArray(value)) { value.forEach(checkActions); return; }
  if (!value || typeof value!=='object') throw Error('action');
  if (!builtInActions.has(value.action) && !Object.hasOwn(actionDefinitions,value.action)) throw Error('action');
  if (value.params?.statePath!==undefined) safePath(value.params.statePath);
  if (value.params?.clearStatePath!==undefined) safePath(value.params.clearStatePath);
  for (const next of [value.onSuccess,value.onError]) {
    if (next?.action) checkActions(next);
    if (next?.set) Object.keys(next.set).forEach(safePath);
  }
}
function validateExpressions(value) {
  if (!value || typeof value!=='object') return;
  for (const [key,child] of Object.entries(value)) {
    if (['$state','$bindState'].includes(key)) safePath(child);
    if (key==='$computed' && !['sum','average','count','min','max'].includes(child)) throw Error('function');
    validateExpressions(child);
  }
}
export function checkedSpec(input,{partial=false}={}) {
  safeValue(input);
  let spec=input;
  if (typeof input.type==='string' && !input.elements) spec=nestedToFlat(input);
  if (!spec.elements || typeof spec.elements!=='object' || Array.isArray(spec.elements)) throw Error('elements');
  if (Object.keys(spec.elements).length>limits.elements) throw Error('elements');
  for (const [key,element] of Object.entries(spec.elements)) {
    if (!key || key.length>160 || !element || !Object.hasOwn(definitions,element.type)) throw Error('component');
    if (!element.props || typeof element.props!=='object' || Array.isArray(element.props)) throw Error('props');
    if (element.children!==undefined && (!Array.isArray(element.children) || !element.children.every(key=>typeof key==='string'))) throw Error('children');
    if (element.slots!==undefined) {
      if (!element.slots || typeof element.slots!=='object') throw Error('slots');
      for (const [slot,keys] of Object.entries(element.slots)) {
        if (slot==='default' || !definitions[element.type].slots?.includes(slot) || !Array.isArray(keys) || !keys.every(key=>typeof key==='string')) throw Error('slot');
      }
    }
    if (element.on) Object.values(element.on).forEach(checkActions);
    if (element.watch) {
      for (const [path,action] of Object.entries(element.watch)) { safePath(path); checkActions(action); }
    }
    if (element.repeat) {
      const path=element.repeat.statePath;
      if (typeof path==='string') safePath(path);
      else if (!path || typeof path.$item!=='string') throw Error('repeat');
    }
    validateExpressions(element.props);
    // Literal props use the exact upstream catalog schemas. Dynamic props are
    // resolved by the upstream renderer with their repeat/state context.
    const containsExpression=JSON.stringify(element.props).includes('"$');
    if (!containsExpression) {
      const schema=definitions[element.type].props;
      const shape=schema.shape;
      const filled=Object.fromEntries(Object.entries(shape).map(([key])=>[key,element.props[key]===undefined ? null : element.props[key]]));
      if (!schema.safeParse({...filled,...element.props}).success) throw Error('props');
    }
  }
  const active=new Set(); const seen=new Set();
  function visit(key,depth) {
    if (depth>16 || active.has(key)) throw Error('cycle');
    if (!spec.elements[key]) { if (!partial) throw Error('reference'); return; }
    if (seen.has(key)) throw Error('shared child');
    active.add(key); seen.add(key);
    const element=spec.elements[key];
    for (const id of [...(element.children??[]),...Object.values(element.slots??{}).flat()]) visit(id,depth+1);
    active.delete(key);
  }
  // Inspect disconnected branches as well, before any of them can be attached.
  for (const key of Object.keys(spec.elements)) {
    active.clear(); seen.clear(); visit(key,0);
  }
  const result=validateSpec(spec,{checkOrphans:!partial});
  const errors=result.issues.filter(issue=>issue.severity==='error' && !(partial && ['missing_root','root_not_found','missing_child'].includes(issue.code)));
  if (errors.length) throw Error('spec');
  if (!partial && (!spec.root || !spec.elements[spec.root])) throw Error('root');
  return spec;
}

/** Compile the same JSONL/YAML protocols the upstream AI SDK adapters emit. */
export function compileSegments(segments,{streaming=false,previousSpec}={}) {
  let spec=previousSpec ? structuredClone(checkedSpec(previousSpec)) : {};
  let wireFormat='json';
  for (const segment of segments) {
    const complete=segment.complete || !streaming;
    if (!segment.complete && !streaming) throw Error('interrupted');
    const text=segment.text;
    if (encoder.encode(text).length>limits.bytes) throw Error('size');
    if (segment.format==='json') {
      try { spec=JSON.parse(text); } catch(error) { if (complete) throw error; continue; }
    } else if (segment.format==='patch') {
      const lines=text.split('\n');
      if (!complete) lines.pop();
      const compiler=createSpecStreamCompiler(structuredClone(spec));
      for (const line of lines.filter(line=>line.trim())) {
        const value=JSON.parse(line); safeValue(value);
        if (value.__json_edit===true) {
          const {__json_edit,...edit}=value;
          compiler.reset(deepMergeSpec(compiler.getResult(),edit));
        } else { checkPatch(value); compiler.push(JSON.stringify(value)+'\n'); }
      }
      spec=compiler.getResult();
    } else if (segment.format==='yaml' || segment.format==='merge') {
      const compiler=createYamlStreamCompiler();
      compiler.push(text);
      const parsed=complete ? compiler.flush().result : compiler.getResult();
      safeValue(parsed);
      spec=segment.format==='merge' ? deepMergeSpec(spec,parsed) : parsed; wireFormat='yaml';
    } else if (segment.format==='yamlPatch') {
      if (!complete) continue;
      const parsed=parseYAML(text);
      if (!Array.isArray(parsed)) throw Error('patch');
      for (const patch of parsed) { checkPatch(patch); applySpecPatch(spec,patch); }
    } else if (segment.format==='diff') {
      if (!complete) continue;
      const original=wireFormat==='yaml'?stringifyYAML(spec):JSON.stringify(spec,null,2)+'\n';
      const patched=applyUnifiedDiff(original,text,{fuzzFactor:0});
      if (patched===false) throw Error('diff');
      if (wireFormat==='yaml') { const compiler=createYamlStreamCompiler();compiler.push(patched);spec=compiler.flush().result; }
      else spec=JSON.parse(patched);
    } else throw Error('format');
    safeValue(spec);
  }
  if (typeof spec.type==='string' && !spec.elements) spec=nestedToFlat(spec);
  if (!spec.elements) return streaming ? null : (()=>{throw Error('empty');})();
  return checkedSpec(spec,{partial:streaming});
}

export function boundedStore(initial={}) {
  safeValue(initial,limits.stateBytes);
  const store=createStateStore(initial); let writes=0; let windowStart=Date.now();
  function validate(updates) {
    if (Date.now()-windowStart>1000) { writes=0; windowStart=Date.now(); }
    if (++writes>100) throw Error('state update loop');
    const next=createStateStore(structuredClone(store.getSnapshot()));
    for (const [path,value] of Object.entries(updates)) { safePath(path); next.set(path,value); }
    safeValue(next.getSnapshot(),limits.stateBytes);
  }
  return {...store,
    set(path,value) { validate({[path]:value}); store.set(path,value); },
    update(updates) { validate(updates); store.update(updates); },
  };
}
export { diffToPatches };

/** The normal model path appends JSONL. Keep the actual upstream compiler alive
 * across arrivals, so no previous patch is parsed or executed a second time. */
export class JSONRenderSessionCompiler {
  constructor(){this.reset();}
  reset(){this.previous='';this.pending='';this.compiler=null;this.processedBytes=0;this.appliedPatches=0;}
  update(segments,{streaming=false,previousSpec}={}){
    if(segments.length!==1||segments[0].format!=='patch')return compileSegments(segments,{streaming,previousSpec});
    const segment=segments[0];
    if(!this.compiler||!segment.text.startsWith(this.previous)){
      this.reset();this.compiler=createSpecStreamCompiler(previousSpec?structuredClone(checkedSpec(previousSpec)):{});
    }
    const delta=segment.text.slice(this.previous.length);this.previous=segment.text;
    this.processedBytes+=encoder.encode(delta).length;this.pending+=delta;
    const lines=this.pending.split('\n');this.pending=lines.pop()??'';
    if(segment.complete||!streaming){if(!segment.complete&&!streaming)throw Error('interrupted');lines.push(this.pending);this.pending='';}
    for(const line of lines.filter(line=>line.trim())){
      const value=JSON.parse(line);safeValue(value);
      if(value.__json_edit===true){const {__json_edit,...edit}=value;this.compiler.reset(deepMergeSpec(this.compiler.getResult(),edit));}
      else{checkPatch(value);this.compiler.push(JSON.stringify(value)+'\n');}
      this.appliedPatches++;
    }
    const spec=this.compiler.getResult();safeValue(spec);
    if(!spec.elements)return streaming?null:(()=>{throw Error('empty');})();
    return checkedSpec(spec,{partial:streaming});
  }
}
