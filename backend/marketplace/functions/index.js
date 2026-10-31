import {onRequest} from 'firebase-functions/v2/https';
import {initializeApp} from 'firebase-admin/app';
import {getAuth} from 'firebase-admin/auth';
import {getFirestore} from 'firebase-admin/firestore';
import {marketplaceAPI} from './api.js';
initializeApp();
const execute = marketplaceAPI(getFirestore(), token => getAuth().verifyIdToken(token,true));
export const marketplace = onRequest({region:'asia-northeast1',maxInstances:10,timeoutSeconds:30,memory:'256MiB',invoker:'public'},async(req,res) => {
  res.set('Cache-Control','no-store');
  if (req.method !== 'POST') return res.status(405).json({error:'POSTが必要です。'});
  if (Number(req.headers['content-length']) > 40000 || Buffer.byteLength(JSON.stringify(req.body ?? {})) > 40000) return res.status(413).json({error:'内容が長すぎます。'});
  try {
    const header = req.headers.authorization;
    const token = header?.startsWith('Bearer ') ? header.slice(7) : null;
    const result = await execute(req.body,token);
    return res.json(result);
  } catch(error) {
    const status = error.status ?? (error.code?.startsWith('auth/') ? 401 : 500);
    // Do not return request content, account identifiers or SDK diagnostics to clients.
    return res.status(status).json({error:status === 500 ? '現在処理できません。後でお試しください。' : error.message});
  }
});
