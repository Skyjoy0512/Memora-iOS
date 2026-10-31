// A serialized transaction fixture. It tests API logic, not Firestore isolation or indexes.
export class Store {
  values = new Map(); queue = Promise.resolve();
  doc(path) { return new Ref(this,path); }
  collection(path) { return new Query(this,path); }
  async runTransaction(callback) {
    let release; const next = new Promise(r => release=r), previous=this.queue; this.queue=next;
    await previous;
    const writes=[]; let wrote=false;
    const tx={get:async ref=>{if(wrote)throw Error('read after write');return ref.get();},
      set:(ref,value,options)=>{wrote=true;writes.push(()=>this.values.set(ref.path,options?.merge ? {...this.values.get(ref.path),...structuredClone(value)} : structuredClone(value)));},
      update:(ref,value)=>{wrote=true;writes.push(()=>this.values.set(ref.path,{...this.values.get(ref.path),...structuredClone(value)}));},
      delete:ref=>{wrote=true;writes.push(()=>this.values.delete(ref.path));}};
    try {const result=await callback(tx);for(const write of writes)write();return result;} finally {release();}
  }
}
class Ref {
  constructor(store,path){this.store=store;this.path=path;this.id=path.split('/').at(-1);}
  collection(name){return this.store.collection(this.path+'/'+name);}
  async get(){const value=this.store.values.get(this.path);return {id:this.id,ref:this,exists:value!==undefined,data:()=>structuredClone(value)};}
}
class Query {
  constructor(store,path,filters=[],order='createdAt',max=Infinity,cursor=null){Object.assign(this,{store,path,filters,order,max,cursor});}
  doc(id){return this.store.doc(this.path+'/'+id);}
  where(field,op,value){if(op!=='==')throw Error(op);return new Query(this.store,this.path,[...this.filters,[field,value]],this.order,this.max,this.cursor);}
  orderBy(field){return new Query(this.store,this.path,this.filters,field,this.max,this.cursor);}
  limit(max){return new Query(this.store,this.path,this.filters,this.order,max,this.cursor);}
  startAfter(snapshot){return new Query(this.store,this.path,this.filters,this.order,this.max,snapshot.id);}
  async get(){let docs=[];for(const [path,value] of this.store.values){if(path.startsWith(this.path+'/')&&path.split('/').length===this.path.split('/').length+1&&this.filters.every(([k,v])=>value[k]===v))docs.push(await this.store.doc(path).get());}
    docs.sort((a,b)=>b.data()[this.order]-a.data()[this.order]||b.id.localeCompare(a.id));
    if(this.cursor)docs=docs.slice(docs.findIndex(d=>d.id===this.cursor)+1);return {docs:docs.slice(0,this.max)};}
}
