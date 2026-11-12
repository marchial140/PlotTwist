const {test,before,after} = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const {initializeTestEnvironment,assertFails,assertSucceeds} = require('@firebase/rules-unit-testing');
const {doc,getDoc,setDoc,updateDoc,collection,getDocs,query,where} = require('firebase/firestore');
const {ref,uploadBytes,getBytes} = require('firebase/storage');
let env;
before(async () => {
  env = await initializeTestEnvironment({projectId:'demo-plottwist',firestore:{rules:fs.readFileSync(path.join(__dirname,'../firestore.rules'),'utf8')},storage:{rules:fs.readFileSync(path.join(__dirname,'../storage.rules'),'utf8')}});
  await env.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(),'groups/cast'),{name:'Private',description:'',ownerID:'owner',timezoneID:'America/Toronto',memberIDs:['owner','friend']});
    await setDoc(doc(context.firestore(),'groups/cast/moments/owner_2026-11-12'),{userID:'owner',weekID:'2026-11-09'});
    await setDoc(doc(context.firestore(),'invitations/secret-hash'),{groupID:'cast'});
  });
});
after(async () => { if (env) await env.cleanup(); });
test('outsiders and anonymous clients cannot read private groups or moments',async () => {
  const outsider = env.authenticatedContext('stranger').firestore();
  await assertFails(getDoc(doc(outsider,'groups/cast')));
  await assertFails(getDoc(doc(outsider,'groups/cast/moments/owner_2026-11-12')));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),'groups/cast')));
});
test('members can query their own groups without listing every group',async () => {
  const db = env.authenticatedContext('friend').firestore();
  await assertSucceeds(getDoc(doc(db,'groups/cast')));
  await assertSucceeds(getDocs(query(collection(db,'groups'),where('memberIDs','array-contains','friend'))));
  await assertFails(getDocs(collection(db,'groups')));
});
test('membership and timezone changes are forbidden even for owner',async () => {
  const db = env.authenticatedContext('owner').firestore();
  await assertFails(updateDoc(doc(db,'groups/cast'),{memberIDs:['owner','friend','intruder']}));
  await assertFails(updateDoc(doc(db,'groups/cast'),{timezoneID:'Etc/UTC'}));
  await assertSucceeds(updateDoc(doc(db,'groups/cast'),{description:'Updated description'}));
});
test('client cannot bypass daily server validation or impersonate another author',async () => {
  const db = env.authenticatedContext('friend').firestore();
  await assertFails(setDoc(doc(db,'groups/cast/moments/spoof'),{userID:'owner',dayKey:'2026-11-12'}));
  await assertFails(setDoc(doc(db,'groups/cast/members/intruder'),{userID:'intruder'}));
  await assertFails(getDoc(doc(db,'invitations/secret-hash')));
});
test('reactions use stable identity, valid type and a real parent moment',async () => {
  const db = env.authenticatedContext('friend').firestore();
  await assertSucceeds(setDoc(doc(db,'groups/cast/moments/owner_2026-11-12/reactions/friend_Fire'),{userID:'friend',type:'Fire'}));
  await assertFails(setDoc(doc(db,'groups/cast/moments/owner_2026-11-12/reactions/owner_Fire'),{userID:'owner',type:'Fire'}));
  await assertFails(setDoc(doc(db,'groups/cast/moments/owner_2026-11-12/reactions/friend_Bad'),{userID:'friend',type:'Bad'}));
  await assertFails(setDoc(doc(db,'groups/cast/moments/missing/reactions/friend_Fire'),{userID:'friend',type:'Fire'}));
});
test('private storage enforces membership, MIME and authorship',async () => {
  const mine = env.authenticatedContext('owner').storage();
  const stranger = env.authenticatedContext('stranger').storage();
  const friend = env.authenticatedContext('friend').storage();
  const file = 'groups/cast/uploads/owner/test.jpg';
  await assertSucceeds(uploadBytes(ref(mine,file),new Uint8Array([1,2,3]),{contentType:'image/jpeg'}));
  await assertFails(uploadBytes(ref(friend,'groups/cast/uploads/owner/spoof.jpg'),new Uint8Array([1]),{contentType:'image/jpeg'}));
  await assertFails(uploadBytes(ref(mine,'groups/cast/uploads/owner/bad.jpg'),new Uint8Array([1]),{contentType:'text/html'}));
  await assertFails(getBytes(ref(stranger,file)));
  await assertSucceeds(getBytes(ref(friend,file)));
});
