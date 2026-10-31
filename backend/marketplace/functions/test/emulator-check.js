import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {initializeApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import {marketplaceAPI} from '../api.js';
if (!process.env.FIRESTORE_EMULATOR_HOST || process.env.GCLOUD_PROJECT !== 'demo-memora') throw Error('Use only the demo-memora Firestore emulator.');
initializeApp({projectId:'demo-memora'});
const db=getFirestore();
const api=marketplaceAPI(db,async uid=>({uid,email_verified:true}));
const id=randomUUID();
try {
 const {post}=await api({action:'publish',requestID:id,authorName:'fixture',acceptedTerms:'2026-10',definition:{version:1,kind:'skill',skill:{name:'fixture',summary:'fixture',instructions:'Read provided records.',declaredToolNames:['read_record']}}},'fixture-owner-'+id);
 assert.equal((await api({action:'list'},null)).posts.some(p=>p.id===id),false);
 await db.doc('marketplacePosts/'+id).update({status:'published'});
 await Promise.all(Array.from({length:10},()=>api({action:'like',postID:id,liked:true},'fixture-reader-'+id)));
 assert.equal((await db.doc('marketplacePosts/'+id).get()).data().likes,1);
 const download=await api({action:'download',postID:id},'fixture-reader-'+id);
 await Promise.all(Array.from({length:10},()=>api({action:'installed',postID:id,version:download.version},'fixture-reader-'+id)));
 assert.equal((await db.doc('marketplacePosts/'+id).get()).data().downloads,1);
 // The public REST API is subject to rules, unlike the Admin SDK used by the service.
 const direct=await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/v1/projects/demo-memora/databases/(default)/documents/marketplacePosts/${id}`);
 assert.equal(direct.status,403);
 console.log('Actual Firestore transactions, retries and unauthenticated direct-read denial passed. Auth identity is a fixture.');
} finally {
 await db.recursiveDelete(db.doc('marketplacePosts/'+id));
 for(const user of ['fixture-owner-','fixture-reader-'])await db.recursiveDelete(db.doc('marketplaceUsers/'+user+id));
 await db.terminate();
}
