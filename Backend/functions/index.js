'use strict';
const {onCall,HttpsError} = require('firebase-functions/v2/https');
const {initializeApp} = require('firebase-admin/app');
const {getFirestore,FieldValue,Timestamp} = require('firebase-admin/firestore');
const {getStorage} = require('firebase-admin/storage');
const {getAuth} = require('firebase-admin/auth');
const crypto = require('node:crypto');
const domain = require('./domain');
initializeApp();
const db = getFirestore();
// App Check is required for deployed callers. Register App Attest before using physical devices.
const callable = handler => onCall({region:'europe-west1',enforceAppCheck:true},async request => {
  if (!request.auth) throw new HttpsError('unauthenticated','Sign in first.');
  return handler(request.auth.uid,request.data || {});
});
function text(value,max) { if (typeof value!=='string' || !value.trim() || value.length>max) throw new HttpsError('invalid-argument','Invalid text.'); return value.trim(); }
function groupRef(id) { return db.collection('groups').doc(text(id,100)); }
function member(group,uid) { if (!group || !group.memberIDs.includes(uid)) throw new HttpsError('permission-denied','Group membership required.'); }
function owner(group,uid) { member(group,uid); if (group.ownerID!==uid) throw new HttpsError('permission-denied','Owner required.'); }
exports.createGroup = callable(async (uid,data) => {
  const name = text(data.name,60), timezoneID = text(data.timezoneID,100);
  try { domain.dayKey(new Date(),timezoneID); } catch { throw new HttpsError('invalid-argument','Unknown time zone.'); }
  const ref = db.collection('groups').doc();
  const batch = db.batch();
  batch.create(ref,{name,timezoneID,description:'',ownerID:uid,memberIDs:[uid],createdAt:FieldValue.serverTimestamp()});
  batch.create(ref.collection('members').doc(uid),{userID:uid,role:'owner',joinedAt:FieldValue.serverTimestamp()});
  await batch.commit(); return {groupID:ref.id};
});
exports.createInvitation = callable(async (uid,data) => {
  const ref = groupRef(data.groupID);
  const code = crypto.randomBytes(24).toString('base64url');
  await db.runTransaction(async tx => {
    const group = (await tx.get(ref)).data(); owner(group,uid);
    tx.create(db.collection('invitations').doc(domain.invitationHash(code)),{groupID:ref.id,createdBy:uid,expiresAt:Timestamp.fromMillis(Date.now()+72*3600*1000)});
  });
  return {code,expiresInHours:72};
});
exports.revokeInvitation = callable(async (uid,data) => {
  const invitation = db.collection('invitations').doc(domain.invitationHash(text(data.code,100)));
  await db.runTransaction(async tx => {
    const invite = (await tx.get(invitation)).data(); if (!invite) return;
    owner((await tx.get(groupRef(invite.groupID))).data(),uid); tx.delete(invitation);
  }); return {ok:true};
});
exports.joinGroup = callable(async (uid,data) => {
  const code = text(data.code,100); let groupID;
  await db.runTransaction(async tx => {
    const invite = (await tx.get(db.collection('invitations').doc(domain.invitationHash(code)))).data();
    if (!invite || invite.expiresAt.toMillis()<=Date.now()) throw new HttpsError('not-found','Invitation unavailable or expired.');
    const ref = groupRef(invite.groupID); const group = (await tx.get(ref)).data();
    if (!group || !domain.canJoin(group,uid)) throw new HttpsError('resource-exhausted','The cast is full.');
    groupID = ref.id;
    if (!group.memberIDs.includes(uid)) {
      tx.update(ref,{memberIDs:FieldValue.arrayUnion(uid)});
      tx.create(ref.collection('members').doc(uid),{userID:uid,role:'member',joinedAt:FieldValue.serverTimestamp()});
    }
  }); return {groupID};
});
exports.publishMoment = callable(async (uid,data) => {
  const ref = groupRef(data.groupID);
  const path = text(data.mediaPath,500);
  if (!path.startsWith(`groups/${ref.id}/uploads/${uid}/`) || path.includes('..')) throw new HttpsError('permission-denied','Not your media.');
  if (!['photo','video'].includes(data.mediaType) || typeof data.caption!=='string' || data.caption.length>180 || !Number.isFinite(data.duration) || data.duration<0 || data.duration>10) throw new HttpsError('invalid-argument','Invalid moment.');
  const [metadata] = await getStorage().bucket().file(path).getMetadata();
  // Strip Firebase's bearer download token before attaching media to a published moment.
  await getStorage().bucket().file(path).setMetadata({metadata:{firebaseStorageDownloadTokens:null}});
  const expected = data.mediaType==='photo' ? 'image/jpeg' : 'video/mp4';
  if (metadata.contentType!==expected || !domain.mediaAllowed(metadata.contentType,Number(metadata.size))) throw new HttpsError('invalid-argument','Invalid media.');
  // Duration here is client-declared. Add a trusted media-probe worker before production;
  // Storage limits and local normalization already cap the V1 payload.
  const now = new Date(); let result;
  await db.runTransaction(async tx => {
    const group = (await tx.get(ref)).data(); member(group,uid);
    const dayKey = domain.dayKey(now,group.timezoneID), weekID = domain.weekKey(now,group.timezoneID);
    const id = `${uid}_${dayKey}`; const momentRef = ref.collection('moments').doc(id);
    const existing = (await tx.get(momentRef)).data();
    tx.set(momentRef,{id,groupID:ref.id,userID:uid,weekID,dayKey,mediaType:data.mediaType,mediaPath:path,caption:data.caption,duration:data.duration,createdAt:existing?.createdAt || Timestamp.fromDate(now),updatedAt:Timestamp.fromDate(now)});
    result = {momentID:id,weekID,dayKey};
  }); return result;
});
exports.deleteMoment = callable(async (uid,data) => {
  const ref = groupRef(data.groupID), moment = ref.collection('moments').doc(text(data.momentID,150)); let path;
  await db.runTransaction(async tx => {
    member((await tx.get(ref)).data(),uid);
    const value = (await tx.get(moment)).data();
    if (!value || value.userID!==uid) throw new HttpsError('permission-denied','Only your own moments can be removed.');
    path = value.mediaPath; tx.delete(moment);
  });
  await db.recursiveDelete(moment);
  if (path) await getStorage().bucket().file(path).delete({ignoreNotFound:true});
  return {ok:true};
});
async function removeMember(groupID,uid,actor) {
  const ref = groupRef(groupID);
  await db.runTransaction(async tx => {
    const group = (await tx.get(ref)).data();
    if (!group) return;
    member(group,actor);
    if (uid!==actor) owner(group,actor);
    if (group.ownerID===uid && group.memberIDs.length>1) throw new HttpsError('failed-precondition','Transfer ownership before leaving your cast.');
    if (group.memberIDs.length===1) tx.delete(ref);
    else tx.update(ref,{memberIDs:FieldValue.arrayRemove(uid)});
    tx.delete(ref.collection('members').doc(uid));
  });
  const moments = await ref.collection('moments').where('userID','==',uid).get();
  for (const moment of moments.docs) await db.recursiveDelete(moment.ref);
  await getStorage().bucket().deleteFiles({prefix:`groups/${groupID}/uploads/${uid}/`});
  const edits = await ref.collection('edits').where('userID','==',uid).get();
  for (const edit of edits.docs) await edit.ref.delete();
}
exports.leaveGroup = callable(async (uid,data) => { await removeMember(text(data.groupID,100),uid,uid); return {ok:true}; });
exports.removeMember = callable(async (uid,data) => { await removeMember(text(data.groupID,100),text(data.userID,128),uid); return {ok:true}; });
exports.transferOwnership = callable(async (uid,data) => {
  const ref = groupRef(data.groupID), target = text(data.userID,128);
  await db.runTransaction(async tx => {
    const group = (await tx.get(ref)).data(); owner(group,uid); member(group,target);
    tx.update(ref,{ownerID:target});
    tx.update(ref.collection('members').doc(uid),{role:'member'});
    tx.update(ref.collection('members').doc(target),{role:'owner'});
  }); return {ok:true};
});
exports.deleteAccount = callable(async uid => {
  const groups = await db.collection('groups').where('memberIDs','array-contains',uid).get();
  // Preflight avoids partial deletions for owners who still need to transfer a group.
  if (groups.docs.some(d => d.data().ownerID===uid && d.data().memberIDs.length>1)) throw new HttpsError('failed-precondition','Transfer ownership of your groups first.');
  for (const group of groups.docs) await removeMember(group.id,uid,uid);
  await db.collection('users').doc(uid).delete();
  await getAuth().deleteUser(uid); return {ok:true};
});
