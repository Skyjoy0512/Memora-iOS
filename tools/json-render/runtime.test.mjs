import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {createPatch} from 'diff';
import {stringify as yaml} from 'yaml';
import {catalog,definitions,directives,functions} from './catalog.mjs';
import {example} from './example.mjs';
import {compileSegments,checkedSpec,boundedStore,safePath,diffToPatches,JSONRenderSessionCompiler} from './engine.mjs';
import {evaluateVisibility,resolveElementProps,createDirectiveRegistry,applySpecPatch,runValidation} from '@json-render/core';
const segment=(format,text,complete=true)=>({format,text,complete});
const compile=(segments,options)=>compileSegments(segments,options);
const minimal={root:'root',elements:{root:{type:'Text',props:{text:'初期値'},children:[]}},state:{items:[1,2],name:''}};
const base=dirname(fileURLToPath(import.meta.url));

test('the full upstream catalog, all extensions and directives are bundled',()=>{
 const asset=JSON.parse(readFileSync(resolve(base,'../../App/Resources/JSONRenderCatalog.json'),'utf8'));
 assert.equal(catalog.componentNames.length,39);
 assert.deepEqual(asset.components,catalog.componentNames);
 assert.ok(catalog.componentNames.includes('Dialog')&&catalog.componentNames.includes('Input')&&catalog.componentNames.includes('Pagination'));
 assert.equal(directives.length,8);
 assert.equal(compile([segment('json',JSON.stringify(example))]).root,'card');
});
test('full JSON, nested specs, YAML, merge and every JSON Patch operation',()=>{
 assert.deepEqual(compile([segment('json',JSON.stringify(minimal))]),minimal);
 assert.deepEqual(compile([segment('yaml',yaml(minimal))]),minimal);
 assert.equal(compile([segment('json',JSON.stringify({type:'Text',props:{text:'入れ子'},children:[]}))]).elements['el-0'].props.text,'入れ子');
 const patches=[{op:'add',path:'/state/items/-',value:3},{op:'replace',path:'/elements/root/props/text',value:'変更後'},
  {op:'copy',from:'/state/items/0',path:'/state/copied'},{op:'move',from:'/state/items/1',path:'/state/moved'},
  {op:'test',path:'/state/copied',value:1},{op:'remove',path:'/state/moved'}];
 const result=compile([segment('json',JSON.stringify(minimal)),segment('patch',patches.map(JSON.stringify).join('\n'))]);
 assert.equal(result.elements.root.props.text,'変更後');assert.deepEqual(result.state.items,[1,3]);assert.equal(result.state.copied,1);assert.ok(!('moved'in result.state));
 assert.throws(()=>compile([segment('json',JSON.stringify(minimal)),segment('patch',JSON.stringify({op:'test',path:'/root',value:'forged'}))]));
 const merge={__json_edit:true,elements:{root:{props:{text:'マージ'}}}};
 assert.equal(compile([segment('patch',JSON.stringify(merge))],{previousSpec:minimal}).elements.root.props.text,'マージ');
 assert.equal(compile([segment('json',JSON.stringify(minimal)),segment('merge','elements:\n  root:\n    props:\n      text: YAML更新\n')]).elements.root.props.text,'YAML更新');
});
test('progressive patches keep valid prefixes and do not parse an unfinished line',()=>{
 const start=[{op:'add',path:'/root',value:'root'},{op:'add',path:'/elements/root',value:minimal.elements.root}].map(JSON.stringify).join('\n')+'\n';
 const incomplete=JSON.stringify({op:'add',path:'/state',value:{title:'日本語と\\と"'}});
 for(let index=0;index<incomplete.length;index++) {
  const result=compile([segment('patch',start+incomplete.slice(0,index),false)],{streaming:true});
  assert.equal(result.elements.root.props.text,'初期値');
 }
 assert.throws(()=>compile([segment('patch',start,false)]));
});
test('unified JSON diff, YAML patch and source-preserving edits',()=>{
 const changed=structuredClone(minimal);changed.elements.root.props.text='差分後';
 const diff=createPatch('spec.json',JSON.stringify(minimal,null,2)+'\n',JSON.stringify(changed,null,2)+'\n');
 assert.deepEqual(compile([segment('json',JSON.stringify(minimal)),segment('diff',diff)]),changed);
 const patch=[{op:'replace',path:'/elements/root/props/text',value:'YAML Patch'}];
 assert.equal(compile([segment('json',JSON.stringify(minimal)),segment('yamlPatch',yaml(patch))]).elements.root.props.text,'YAML Patch');
 assert.throws(()=>compile([segment('json',JSON.stringify(minimal)),segment('diff',diff.replace('初期値','異なる原文'))]));
 const applied=structuredClone(minimal);for(const patch of diffToPatches(minimal,changed))applySpecPatch(applied,patch);assert.deepEqual(applied,changed);
});
test('conditions, expressions, bindings, computed functions and all directives use upstream evaluation',()=>{
 const context={stateModel:{enabled:true,name:'Memora',amount:4,items:[1,2,3]},functions,directives:createDirectiveRegistry(directives)};
 assert.equal(evaluateVisibility({$and:[{$state:'/enabled',eq:true},{$or:[{$state:'/amount',gte:4},false]}]},context),true);
 const element={type:'Text',props:{label:{$template:'${/name}'},count:{$count:{$state:'/items'}},math:{$math:'multiply',a:{$state:'/amount'},b:2},bound:{$bindState:'/name'},sum:{$computed:'sum',args:{values:{$state:'/items'}}},condition:{$cond:{$state:'/enabled'},$then:'有効',$else:'無効'}}};
 const result=resolveElementProps(element,context);assert.equal(result.props.label,'Memora');assert.equal(result.props.count,3);assert.equal(result.props.math,8);assert.equal(result.props.sum,6);assert.equal(result.props.condition,'有効');
 assert.equal(result.props.bound,'Memora');
});
test('state store is reactive and bounded, without granting app permissions',()=>{
 const store=boundedStore({items:[],name:''});let changes=0;const cancel=store.subscribe(()=>changes++);
 store.set('/name','名前');store.update({'/items':[1,2],'/flag':true});assert.equal(store.get('/name'),'名前');assert.equal(changes,2);cancel();
 for(const path of ['/__proto__/polluted','/constructor/prototype/x','/x/prototype'])assert.throws(()=>store.set(path,true));
 assert.equal({}.polluted,undefined);assert.throws(()=>store.set('/items',Array(201).fill(1)));
});
test('unknown components/actions, forged paths, cycles, bad props and excessive specs are refused',()=>{
 for(const mutate of [s=>s.elements.root.type='WebView',s=>s.elements.root.props.text={},s=>s.elements.root.children=['root'],
  s=>s.elements.root.on={press:{action:'deleteEverything'}},s=>s.elements.root.watch={'/__proto__/x':{action:'setState',params:{statePath:'/x',value:1}}},
  s=>s.elements.root.slots={unknown:['root']},s=>s.elements.root.props.text={$computed:'eval',args:{code:'bad'}},s=>s.state={items:Array(201).fill(1)}]) {
  const value=structuredClone(minimal);mutate(value);assert.throws(()=>checkedSpec(value));
 }
 for(const op of [{op:'add',path:'/__proto__/x',value:true},{op:'copy',path:'/state/x',from:'/constructor/prototype'},{op:'execute',path:'/state',value:{}}])assert.throws(()=>compile([segment('patch',JSON.stringify(op))],{previousSpec:minimal}));
 assert.equal({}.x,undefined);
});
test('the shipped HTML contains the upstream runtime and an exact CSP hash, with no remote resources',()=>{
 const html=readFileSync(resolve(base,'../../App/Resources/JSONRenderRuntime.html'),'utf8');
 const script=html.match(/<script>([\s\S]*)<\/script>/)[1];
 const hash=createHash('sha256').update(script).digest('base64');
 assert.ok(html.includes("script-src 'sha256-"+hash+"'"));assert.ok(html.includes("connect-src 'none'"));assert.ok(html.includes("frame-src 'none'"));
 assert.ok(!html.includes('<script src=')&&!html.includes('<iframe'));
 const notices=readFileSync(resolve(base,'../../App/Resources/JSONRenderLicenses.txt'),'utf8');
 for(const name of ['@json-render/core','@json-render/react','@json-render/shadcn','@json-render/yaml','@json-render/directives','react-dom'])assert.ok(notices.includes(name));
});

test('the production session scans only appended JSONL and never reapplies completed patches',()=>{
 const text=[{op:'add',path:'/root',value:'root'},{op:'add',path:'/elements/root',value:minimal.elements.root},{op:'add',path:'/state',value:{items:['日本語']}}].map(JSON.stringify).join('\n');
 const compiler=new JSONRenderSessionCompiler();let prefix='';
 for(const char of text){prefix+=char;compiler.update([segment('patch',prefix,false)],{streaming:true});}
 const result=compiler.update([segment('patch',text,true)],{streaming:false});
 assert.equal(result.elements.root.props.text,'初期値');assert.equal(compiler.appliedPatches,3);assert.equal(compiler.processedBytes,new TextEncoder().encode(text).length);
 compiler.update([segment('patch',text,true)],{streaming:false});assert.equal(compiler.appliedPatches,3);
});
