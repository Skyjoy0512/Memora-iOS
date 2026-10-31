import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {Store} from './store.js';
import {marketplaceAPI} from '../api.js';
import {definition} from '../definition.js';
const skill={version:1,kind:'skill',skill:{name:'会議の確認',summary:'原文から整理',instructions:'許可された記録だけを読む。',keywords:['会議'],declaredToolNames:['read_record']}};
function setup(){const db=new Store();const api=marketplaceAPI(db,async token=>{if(token==='forged')throw {status:401};return {uid:token,email_verified:token!=='unverified'};});return {db,api};}
async function published(db,api){const {post}=await api({action:'publish',definition:skill,authorName:'作者',requestID:randomUUID(),acceptedTerms:'2026-10'},'owner');db.values.get('marketplacePosts/'+post.id).status='published';return post;}
test('requires verified identity; rejects unknown tools and invalid definitions',async()=>{
 const {api}=setup();await assert.rejects(()=>api({action:'publish'},null),e=>e.status===401);
 await assert.rejects(()=>api({action:'publish'},'unverified'),e=>e.status===403);
 await assert.rejects(()=>api({action:'mine'},'forged'),e=>e.status===401);
 assert.throws(()=>definition({...skill,skill:{...skill.skill,declaredToolNames:['shell_exec']}}));
 assert.throws(()=>definition({...skill,skill:{...skill.skill,instructions:'x'.repeat(6001)}}));
 assert.throws(()=>definition({version:1,kind:'template',template:{title:'空',detail:'',category:'meetings',sections:[]}}));
});
test('publication is pending, immutable and idempotent; cannot forge counters/author',async()=>{
 const {db,api}=setup(),request={action:'publish',definition:skill,authorName:'作者',requestID:randomUUID(),acceptedTerms:'2026-10',likes:999,authorID:'other',status:'published'};
 const {post}=await api(request,'owner');assert.equal(post.status,'pending');assert.equal(post.likes,0);assert.equal(post.authorID,'owner');
 assert.equal((await api(request,'owner')).post.id,post.id);
 await assert.rejects(()=>api({...request,authorName:'別の名'},'owner'),e=>e.status===409);
 assert.equal((await api({action:'list'},null)).posts.length,0);
 assert.equal((await api({action:'mine'},'owner')).posts.length,1);
 await assert.rejects(()=>api({action:'remove',postID:post.id},'other'),e=>e.status===403);
 await api({action:'remove',postID:post.id},'owner');assert.equal(db.values.get('marketplacePosts/'+post.id).status,'removed');
});
test('concurrent desired likes and retries count each account once, unlike is idempotent',async()=>{
 const {db,api}=setup(),post=await published(db,api);
 await Promise.all(Array.from({length:30},(_,i)=>api({action:'like',postID:post.id,liked:true,likes:999},'user'+i)));
 await Promise.all(Array.from({length:30},()=>api({action:'like',postID:post.id,liked:true},'user1')));
 assert.equal(db.values.get('marketplacePosts/'+post.id).likes,30);
 await api({action:'like',postID:post.id,liked:false},'user1');await api({action:'like',postID:post.id,liked:false},'user1');
 assert.equal(db.values.get('marketplacePosts/'+post.id).likes,29);
});
test('downloads require a transfer receipt and a saved-version acknowledgement; retries never double count',async()=>{
 const {db,api}=setup(),post=await published(db,api);
 await assert.rejects(()=>api({action:'installed',postID:post.id,version:post.version},'user'),e=>e.status===409);
 const download=await api({action:'download',postID:post.id},'user');assert.equal(db.values.get('marketplacePosts/'+post.id).downloads,0);
 await assert.rejects(()=>api({action:'installed',postID:post.id,version:'tampered'},'user'),e=>e.status===409);
 await Promise.all(Array.from({length:20},()=>api({action:'installed',postID:post.id,version:download.version},'user')));
 assert.equal(db.values.get('marketplacePosts/'+post.id).downloads,1);
});
test('reports deduplicate and quarantine only after three distinct accounts',async()=>{
 const {db,api}=setup(),post=await published(db,api);
 for(let i=0;i<5;i++)await api({action:'report',postID:post.id,reason:'spam'},'user1');
 assert.equal(db.values.get('marketplacePosts/'+post.id).status,'published');
 await api({action:'report',postID:post.id,reason:'rights'},'user2');await api({action:'report',postID:post.id,reason:'other'},'user3');
 assert.equal((await api({action:'list'},null)).posts.length,0);
 await assert.rejects(()=>api({action:'download',postID:post.id},'user'),e=>e.status===404);
});
test('popular ordering and bounded pagination are based on server counters',async()=>{
 const {db,api}=setup();for(let i=0;i<10;i++)await published(db,api);
 const hot=await published(db,marketplaceAPI(db,async()=>({uid:'second',email_verified:true})));
 await api({action:'like',postID:hot.id,liked:true},'reader');
 assert.equal((await api({action:'list'},null)).posts[0].id,hot.id);
 const first=(await api({action:'mine'},'owner')).posts;assert.equal(first.length,10);
 await assert.rejects(()=>api({action:'publish',definition:skill,authorName:'作者',requestID:randomUUID(),acceptedTerms:'2026-10'},'owner'),e=>e.status===429);
});

test('pagination returns only 20 entries with a non-overlapping next page',async()=>{
 const {db}=setup();
 const api=marketplaceAPI(db,async uid=>({uid,email_verified:true}));
 for(let i=0;i<24;i++)await published(db,marketplaceAPI(db,async()=>({uid:'author'+i,email_verified:true})));
 const first=await api({action:'list'},null);assert.equal(first.posts.length,20);assert.ok(first.nextCursor);
 const second=await api({action:'list',after:first.nextCursor},null);assert.equal(second.posts.length,4);assert.equal(second.nextCursor,null);
 assert.equal(new Set([...first.posts,...second.posts].map(p=>p.id)).size,24);
});
