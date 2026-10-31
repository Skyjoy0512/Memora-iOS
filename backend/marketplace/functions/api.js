import {APIError, definition, metadata, versionID, identifier, authorName} from './definition.js';

export function marketplaceAPI(db, auth) {
  const posts = db.collection('marketplacePosts');
  const publicPost = doc => {
    const p = doc.data();
    return {id:doc.id,title:p.title,summary:p.summary,definition:p.definition,authorID:p.authorID,authorName:p.authorName,
      createdAt:p.createdAt,status:p.status,likes:p.likes,downloads:p.downloads,version:p.version};
  };
  return async function execute(input, token) {
    if (!input || typeof input !== 'object') throw new APIError(400,'リクエストを確認してください。');
    const user = token ? await auth(token) : null;
    const authenticated = () => { if (!user?.uid || user.marketplaceBanned) throw new APIError(401,'コミュニティにログインしてください。'); };
    const verified = () => { authenticated(); if (!user.email_verified) throw new APIError(403,'メールアドレスの確認を完了してください。'); };
    if (input.action === 'list' || input.action === 'mine') {
      if (input.action === 'mine') authenticated();
      const field = input.sort === 'latest' || input.action === 'mine' ? 'createdAt' : 'score';
      let query = input.action === 'mine' ? posts.where('authorID','==',user.uid) : posts.where('status','==','published');
      query = query.orderBy(field,'desc');
      if (input.after) {
        const cursor = await posts.doc(identifier(input.after)).get();
        if (!cursor.exists || (input.action === 'mine' ? cursor.data().authorID !== user.uid : cursor.data().status !== 'published')) throw new APIError(400,'一覧を再読み込みしてください。');
        query = query.startAfter(cursor);
      }
      const snapshot = await query.limit(21).get();
      const docs = snapshot.docs.slice(0,20);
      const result = await Promise.all(docs.map(async doc => {
        const data = publicPost(doc);
        const liked = user ? (await doc.ref.collection('likes').doc(user.uid).get()).exists : false;
        return {...data,liked};
      }));
      return {posts:result,nextCursor:snapshot.docs.length > 20 ? docs.at(-1).id : null};
    }
    verified();
    const day = new Date().toISOString().slice(0,10);
    const usageRef = db.doc(`marketplaceUsers/${user.uid}/daily/${day}`);
    if (input.action === 'publish') {
      if (input.acceptedTerms !== '2026-10') throw new APIError(400,'公開ルールを確認してください。');
      const content = definition(input.definition), id = identifier(input.requestID), name = authorName(input.authorName);
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)) throw new APIError(400,'投稿IDを確認してください。');
      const ref = posts.doc(id);
      return db.runTransaction(async tx => {
        const [existing,usage] = await Promise.all([tx.get(ref),tx.get(usageRef)]);
        if (existing.exists) {
          if (existing.data().authorID !== user.uid || existing.data().version !== versionID(content) || existing.data().authorName !== name) throw new APIError(409,'投稿内容が変わりました。開き直してください。');
          return {post:publicPost(existing)};
        }
        if ((usage.data()?.posts ?? 0) >= 10) throw new APIError(429,'今日の投稿上限に達しました。');
        const post = {...metadata(content),definition:content,version:versionID(content),authorID:user.uid,authorName:name,
          createdAt:Date.now(),status:'pending',likes:0,downloads:0,score:0};
        tx.set(ref,post); tx.set(usageRef,{posts:(usage.data()?.posts ?? 0)+1},{merge:true});
        return {post:{id,...post}};
      });
    }
    const ref = posts.doc(identifier(input.postID));
    if (input.action === 'remove') {
      return db.runTransaction(async tx => {
        const post = await tx.get(ref);
        if (!post.exists || post.data().authorID !== user.uid) throw new APIError(403,'自分の投稿だけ取り下げられます。');
        tx.update(ref,{status:'removed'}); return {ok:true};
      });
    }
    return db.runTransaction(async tx => {
      const post = await tx.get(ref);
      if (!post.exists || post.data().status !== 'published') throw new APIError(404,'この投稿は公開されていません。');
      const data = post.data();
      const event = ref.collection(input.action === 'like' ? 'likes' : input.action === 'report' ? 'reports' : 'installs').doc(user.uid);
      const [previous,usage] = await Promise.all([tx.get(event),tx.get(usageRef)]);
      const actions = usage.data()?.actions ?? 0;
      if (actions >= 200) throw new APIError(429,'しばらくしてから再度お試しください。');
      if (input.action === 'like') {
        if (typeof input.liked !== 'boolean') throw new APIError(400,'操作を確認してください。');
        const delta = Number(input.liked) - Number(previous.exists);
        const likes = Math.max(0,data.likes+delta);
        if (delta > 0) tx.set(event,{createdAt:Date.now()});
        if (delta < 0) tx.delete(event);
        tx.update(ref,{likes,score:likes*3+data.downloads});
        tx.set(usageRef,{actions:actions+1},{merge:true});
        return {likes,liked:input.liked};
      }
      if (input.action === 'report') {
        const reason = ['spam','unsafe','rights','other'].includes(input.reason) ? input.reason : 'other';
        if (!previous.exists) {
          const reports = (data.reportCount ?? 0)+1;
          tx.set(event,{reason,createdAt:Date.now()});
          tx.update(ref,{reportCount:reports,...(reports >= 3 ? {status:'quarantined'} : {})});
        }
        tx.set(usageRef,{actions:actions+1},{merge:true}); return {ok:true};
      }
      if (input.action === 'download') {
        // A receipt is issued before transfer; only the later successful local save counts.
        const receipt = ref.collection('receipts').doc(user.uid);
        tx.set(receipt,{version:data.version,createdAt:Date.now()});
        tx.set(usageRef,{actions:actions+1},{merge:true});
        return {definition:data.definition,version:data.version};
      }
      if (input.action === 'installed') {
        const receipt = await tx.get(ref.collection('receipts').doc(user.uid));
        if (!receipt.exists || receipt.data().version !== input.version || data.version !== input.version) throw new APIError(409,'もう一度追加してください。');
        const downloads = data.downloads + Number(!previous.exists);
        if (!previous.exists) tx.set(event,{version:input.version,createdAt:Date.now()});
        tx.update(ref,{downloads,score:data.likes*3+downloads});
        tx.set(usageRef,{actions:actions+1},{merge:true});
        return {downloads};
      }
      throw new APIError(400,'対応していない操作です。');
    });
  };
}
