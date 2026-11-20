import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {JSDOM} from 'jsdom';
import {fileURLToPath} from 'node:url';
import {dirname,resolve} from 'node:path';
import {catalog,definitions,directives,functions} from './catalog.mjs';
import {boundedStore,checkedSpec} from './engine.mjs';
import {example} from './example.mjs';
const base=dirname(fileURLToPath(import.meta.url));
const dom=new JSDOM('<!doctype html><html><body></body></html>',{url:'https://local.test',pretendToBeVisual:true});
for(const key of ['window','document','HTMLElement','HTMLInputElement','HTMLButtonElement','HTMLFormElement','HTMLFieldSetElement','HTMLOptionElement','SVGElement','Element','Node','DocumentFragment','MutationObserver','Event','CustomEvent','MouseEvent','KeyboardEvent'])globalThis[key]=dom.window[key];
for(const key of Object.getOwnPropertyNames(dom.window)) { if (/^[A-Z]/.test(key) && !(key in globalThis)) globalThis[key]=dom.window[key]; }
Object.defineProperty(globalThis,'navigator',{value:dom.window.navigator,configurable:true});
globalThis.getComputedStyle=dom.window.getComputedStyle;
globalThis.requestAnimationFrame=dom.window.requestAnimationFrame.bind(dom.window);
globalThis.cancelAnimationFrame=dom.window.cancelAnimationFrame.bind(dom.window);
globalThis.ResizeObserver=class {observe(){}unobserve(){}disconnect(){}};
dom.window.ResizeObserver=globalThis.ResizeObserver;
dom.window.matchMedia=()=>({matches:false,addEventListener(){},removeEventListener(){},addListener(){},removeListener(){}});
dom.window.PointerEvent=dom.window.MouseEvent;
dom.window.HTMLElement.prototype.scrollIntoView=function(){};
dom.window.HTMLElement.prototype.hasPointerCapture=()=>false;
dom.window.HTMLElement.prototype.setPointerCapture=function(){};
dom.window.HTMLElement.prototype.releasePointerCapture=function(){};
globalThis.IS_REACT_ACT_ENVIRONMENT=true;
await build({entryPoints:[resolve(base,'components.jsx')],outfile:resolve(base,'.test-components.mjs'),bundle:true,packages:'external',format:'esm',platform:'node',logLevel:'silent'});
const React=await import('react');
const {renderToString}=await import('react-dom/server');
const {JSONUIProvider,Renderer}=await import('@json-render/react');
const {registry}=await import('./.test-components.mjs');
const {render,cleanup,screen,waitFor}=await import('@testing-library/react');
const userEvent=(await import('@testing-library/user-event')).default;
test.afterEach(()=>cleanup());
const h=React.createElement;
function normalize(spec){const next=structuredClone(spec);for(const element of Object.values(next.elements)){for(const [key,schema]of Object.entries(definitions[element.type].props.shape)){if(element.props[key]===undefined&&schema.isNullable())element.props[key]=null;}}return next;}
function surface(spec,store,handlers={}){return h(JSONUIProvider,{registry,store,handlers,directives,functions},h(Renderer,{registry,spec:normalize(spec)}));}
const fixtures={
 Card:{title:'カード'},Stack:{},Grid:{columns:2},Separator:{},Tabs:{tabs:[{label:'概要',value:'overview'}]},Accordion:{items:[{title:'項目',content:'本文'}]},Collapsible:{title:'折り畳み'},Dialog:{title:'ダイアログ',openPath:'/open'},Drawer:{title:'ドロワー',openPath:'/open'},Carousel:{items:[{title:'項目',description:'本文'}]},Table:{columns:['列'],rows:[['値']]},Heading:{text:'見出し'},Text:{text:'本文'},Image:{alt:'画像'},Avatar:{name:'名前'},Badge:{text:'ラベル'},Alert:{title:'通知'},Progress:{value:25},Skeleton:{},Spinner:{},Tooltip:{text:'ヒント',content:'説明'},Popover:{trigger:'開く',content:'内容'},Input:{label:'入力',name:'input'},Textarea:{label:'本文入力',name:'textarea'},Select:{label:'選択',name:'select',options:['A','B']},Checkbox:{label:'確認',name:'checkbox'},Radio:{label:'候補',name:'radio',options:['A','B']},Switch:{label:'切替',name:'switch'},Slider:{label:'値'},Button:{label:'実行'},Link:{label:'リンク',href:'https://example.test'},DropdownMenu:{label:'メニュー',items:[{label:'候補',value:'a'}]},Toggle:{label:'トグル'},ToggleGroup:{items:[{label:'候補',value:'a'}]},ButtonGroup:{buttons:[{label:'候補',value:'a'}]},Pagination:{totalPages:3},Metric:{label:'指標',value:3},BarChart:{title:'件数',items:[{label:'A',value:2}]},Panel:{label:'パネル'},
};
test('every one of the 36 upstream components and all 3 app components renders through the production registry',()=>{
 assert.deepEqual(Object.keys(registry).sort(),catalog.componentNames.toSorted());
 for(const type of catalog.componentNames){const spec={root:'one',state:{open:false},elements:{one:{type,props:fixtures[type],children:[]}}};checkedSpec(spec);assert.doesNotThrow(()=>renderToString(surface(spec,boundedStore(spec.state))),type);}
});
test('real DOM: input binding, validation, tabs, visibility, repeat item binding, slots and dialog',async()=>{
 const store=boundedStore(example.state);const user=userEvent.setup({document:dom.window.document});
 render(surface(example,store));
 const input=screen.getByRole('textbox',{name:'表示する名前'});await user.type(input,'Ken');
 assert.equal(store.get('/name'),'Ken');assert.ok(screen.getByText('こんにちは、Kenさん'));
 await user.click(screen.getByRole('tab',{name:'詳細'}));assert.equal(store.get('/tab'),'detail');assert.ok(screen.getByText('詳細タブの表示内容です。'));
 assert.ok(screen.getByText('名前付きスロット'));await user.click(screen.getByRole('switch',{name:'補足を表示'}));assert.equal(store.get('/show'),false);assert.equal(screen.queryByText('名前付きスロット'),null);
 await user.click(screen.getByRole('checkbox',{name:'検証用A'}));assert.equal(store.get('/items/0/done'),true);
 await user.clear(input);await user.type(input,'K');await user.tab();await waitFor(()=>assert.ok(screen.getByText('2文字以上で入力してください。')));
 await user.click(screen.getByRole('button',{name:'ダイアログを開く'}));await waitFor(()=>assert.ok(screen.getByRole('dialog')));assert.ok(screen.getByText('本家のDialogコンポーネントです。'));
 cleanup();
});
test('real DOM: state watchers, action confirmation, resolved parameters and onSuccess chaining',async()=>{
 const spec={root:'stack',state:{name:'',seen:'',copied:false},elements:{
 stack:{type:'Stack',props:{},children:['input','watch','button','done']},
 input:{type:'Input',props:{name:'name',label:'名前',value:{$bindState:'/name'}},children:[]},
 watch:{type:'Text',props:{text:{$state:'/seen'}},watch:{'/name':{action:'setState',params:{statePath:'/seen',value:'変更済み'}}},children:[]},
 button:{type:'Button',props:{label:'確認してコピー'},on:{press:{action:'copyText',params:{text:{$state:'/name'}},confirm:{title:'内容の確認',message:'コピーしますか？',confirmLabel:'実行',cancelLabel:'取消'},onSuccess:{set:{'/copied':true}}}},children:[]},
 done:{type:'Text',props:{text:'コピー完了'},visible:{$state:'/copied',eq:true},children:[]}
 }};
 const store=boundedStore(spec.state);let copied;const user=userEvent.setup({document:dom.window.document});
 render(surface(spec,store,{copyText:params=>{copied=params.text;}}));
 await user.type(screen.getByRole('textbox',{name:'名前'}),'Memora');await waitFor(()=>assert.equal(store.get('/seen'),'変更済み'));
 await user.click(screen.getByRole('button',{name:'確認してコピー'}));assert.equal(copied,undefined);assert.ok(screen.getByText('内容の確認'));
 await user.click(screen.getByRole('button',{name:'実行'}));await waitFor(()=>assert.equal(copied,'Memora'));await waitFor(()=>assert.ok(screen.getByText('コピー完了')));
 cleanup();
});

test('generated charts place losses before zero and keep zero-length bars invisible', () => {
 const spec = {
  root: 'chart',
  state: {},
  elements: {
   chart: {
    type: 'BarChart',
    props: {
     title: '増減',
     unit: '件',
     items: [{label: '前月', value: -4}, {label: '今月', value: 2}, {label: '変化なし', value: 0}],
    },
    children: [],
   },
  },
 };
 const {container} = render(surface(spec, boundedStore(spec.state)));
 const bars = [...container.querySelectorAll('.chart-bar')];
 assert.deepEqual(bars.map(bar => [bar.style.insetInlineStart, bar.style.width]), [
  ['0%', '50%'], ['50%', '25%'], ['50%', '0%'],
 ]);
 assert.ok(screen.getByText('-4 件'));
 assert.ok(screen.getByText('0 件'));
 assert.ok(bars.every(bar => bar.parentElement.getAttribute('aria-hidden') === 'true'));
});
