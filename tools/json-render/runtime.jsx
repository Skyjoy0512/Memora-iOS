import React, {useEffect, useMemo, useState, Component} from 'react';
import {createRoot} from 'react-dom/client';
import {JSONUIProvider, Renderer} from '@json-render/react';
import {registry} from './components.jsx';
import {catalog, directives, functions, actionDefinitions} from './catalog.mjs';
import {JSONRenderSessionCompiler, boundedStore, safeValue, limits} from './engine.mjs';

let receive; let current=null; let gestureAt=0; let nextRequest=0; const pending=new Map();
const post=body=>window.webkit?.messageHandlers?.jsonRender?.postMessage({token:current?.token,fingerprint:current?.fingerprint,...body});
for (const name of ['click','keydown']) document.addEventListener(name,event=>{
  if (event.isTrusted && (name==='click' || ['Enter',' '].includes(event.key))) gestureAt=Date.now();
},true);
function nativeAction(action,params) {
  if (!current?.interactive || Date.now()-gestureAt>2000) return Promise.reject(Error('操作ボタンから実行してください。'));
  const parsed=actionDefinitions[action]?.params.safeParse(params);
  if (!parsed?.success) return Promise.reject(Error('操作の入力を確認してください。'));
  gestureAt=0;
  return new Promise((resolve,reject)=>{
    const id=String(++nextRequest);
    const timeout=setTimeout(()=>{pending.delete(id);reject(Error('操作を完了できませんでした。'));},120000);
    pending.set(id,{resolve,reject,timeout}); post({kind:'action',id,action,params:parsed.data});
  });
}

class RenderBoundary extends Component {
  state={failed:false};
  static getDerivedStateFromError(){return {failed:true};}
  componentDidCatch(){post({kind:'error'});}
  render(){return this.state.failed ? <p role="alert">表示を読み込めませんでした。本文を確認してください。</p> : this.props.children;}
}
function normalized(spec) {
  const result=structuredClone(spec);
  for (const element of Object.values(result.elements)) {
    const shape=catalog.data.components[element.type].props.shape;
    for (const [key,schema] of Object.entries(shape)) {
      if (element.props[key]===undefined && schema.isNullable()) element.props[key]=null;
    }
  }
  return result;
}
function snapshotState(spec,store) {
  const state=structuredClone(store.getSnapshot());
  // Password inputs remain local to the active web view, never in SQLite/copy.
  if (Object.values(spec.elements).some(e=>e.type==='Input'&&e.props.type==='password')) return {};
  safeValue(state,limits.stateBytes); return state;
}
function Runtime() {
  const [compiler]=useState(()=>new JSONRenderSessionCompiler());
  const [revision,setRevision]=useState(0); const [spec,setSpec]=useState(null); const [store,setStore]=useState(null);
  const [error,setError]=useState(false); const [status,setStatus]=useState('');
  useEffect(()=>{
    receive=payload=>{
      const reset=!current || current.identity!==payload.identity;
      current=payload;
      try {
        if(reset) compiler.reset();
        const parsed=compiler.update(payload.segments,{streaming:payload.streaming,previousSpec:payload.previousSpec});
        document.documentElement.classList.toggle('dark',payload.dark);
        document.documentElement.style.fontSize=`${payload.fontSize}px`;
        document.documentElement.dataset.motion=payload.reduceMotion?'reduced':'full';
        document.documentElement.dataset.streaming=payload.streaming?'true':'false';
        if (parsed) {
          const next=normalized(parsed);
          if (reset || !store) {
            const initial=payload.savedState??next.state??{};
            const nextStore=boundedStore(initial);
            setStore(nextStore); setRevision(value=>value+1);
          } else if (payload.streaming) {
            // Preserve person edits. Only model stream revisions seed state;
            // settled rerenders and color/size changes do not reset inputs.
            if (JSON.stringify(spec?.state)!==JSON.stringify(next.state)) {
              const nextStore=boundedStore(next.state??{}); setStore(nextStore);
            }
          }
          setSpec(next); setError(false);
        } else if (!payload.streaming) { setError(true); }
      } catch { setError(true); if (!payload.streaming) post({kind:'error'}); }
    };
    return ()=>{receive=null;};
  },[store,spec]);
  useEffect(()=>{ post({kind:'ready'}); },[]);
  useEffect(()=>{
    if (!store || !spec || !current) return;
    let timer;
    const publish=()=>{
      clearTimeout(timer); timer=setTimeout(()=>{
        if (current?.streaming) return;
        try {
          const surface=document.getElementById('surface');
          const labels=Array.from(surface?.querySelectorAll('label')??[]);
          const fields=Array.from(surface?.querySelectorAll('input:not([type=password]):not([type=hidden]),textarea,select')??[])
            .filter(field=>field.type!=='checkbox'&&field.type!=='radio')
            .map(field=>(labels.find(label=>label.htmlFor===field.id)?.textContent??field.name)+': '+field.value);
          const text=((surface?.innerText??'')+(fields.length?'\n\n'+fields.join('\n'):'')).slice(0,32000);
          post({kind:'state',state:snapshotState(spec,store),spec,text});
        } catch {setStatus('入力内容が保存上限を超えています。');}
      },180);
    };
    const unsubscribe=store.subscribe(publish); publish();
    return ()=>{clearTimeout(timer);unsubscribe();};
  },[store,spec]);
  const handlers=useMemo(()=>Object.fromEntries(Object.keys(actionDefinitions).map(action=>[action,async params=>{
    try { const result=await nativeAction(action,params);setStatus(result?.message??'');return result; }
    catch(error) {setStatus(error.message);throw error;}
  }])),[]);
  return <>
    <div id="surface" aria-label="生成された回答" aria-busy={current?.streaming??true}>
      {error?<p role="alert">構造化表示を読み込めませんでした。本文を確認してください。</p>:spec&&store&&
        <RenderBoundary key={revision}><JSONUIProvider registry={registry} store={store} handlers={handlers}
          directives={directives} functions={functions} navigate={path=>store.set('/navigation/path',path)}>
          <Renderer spec={spec} registry={registry} loading={current?.streaming}/>
        </JSONUIProvider></RenderBoundary>}
    </div>
    {status&&<p role="status" className="action-status">{status}</p>}
  </>;
}
window.memoraJSONRender={
  receive(payload){ if(receive) receive(payload); else current=payload; },
  setViewport(top,height){
    document.documentElement.style.setProperty('--memora-viewport-top',`${top}px`);
    document.documentElement.style.setProperty('--memora-viewport-height',`${height}px`);
  },
  resolve(id,ok,result){const call=pending.get(id);if(!call)return;clearTimeout(call.timeout);pending.delete(id);ok?call.resolve(result):call.reject(Error(result?.message??'操作は実行されませんでした。'));},
};
const root=createRoot(document.getElementById('root'));
root.render(<Runtime/>);
// scrollHeight is at least the current viewport height, so it cannot report a
// smaller answer after a disclosure or conditional section closes.
new ResizeObserver(()=>post({kind:'height',height:Math.ceil(document.body.getBoundingClientRect().height)})).observe(document.body);
new MutationObserver(()=>{
  // The upstream action confirmation uses an inline fixed flex layer, while
  // shadcn dialogs/drawers expose stable slot attributes.
  for(const layer of document.querySelectorAll('#root div[style*="position: fixed"]')) {
    if(layer.style.display==='flex'&&layer.style.alignItems==='center')layer.dataset.memoraConfirmation='true';
  }
  if(document.querySelector('[data-slot="dialog-content"][data-state="open"],[data-slot="drawer-content"][data-state="open"],[data-memora-confirmation]'))post({kind:'viewport'});
}).observe(document.body,{childList:true,subtree:true});
window.addEventListener('unhandledrejection',event=>{event.preventDefault();post({kind:'error'});});
document.addEventListener('click',event=>{
  const link=event.target.closest('a[href]');
  if (link && !link.getAttribute('href').startsWith('#')) {
    event.preventDefault();
    nativeAction('openURL',{url:link.getAttribute('href')}).catch(()=>{});
  }
},true);
