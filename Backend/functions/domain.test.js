const {test} = require('node:test');
const assert = require('node:assert/strict');
const {dayKey,weekKey,invitationHash,canJoin,mediaAllowed} = require('./domain');
test('Monday boundary is evaluated in group time zone',() => {
  assert.equal(weekKey(new Date('2026-11-09T04:59:59Z'),'America/Toronto'),'2026-11-02');
  assert.equal(weekKey(new Date('2026-11-09T05:00:00Z'),'America/Toronto'),'2026-11-09');
});
test('DST and ISO year boundary do not shift local week',() => {
  assert.equal(weekKey(new Date('2026-03-08T07:30:00Z'),'America/Toronto'),'2026-03-02');
  assert.equal(weekKey(new Date('2027-01-01T12:00:00Z'),'Europe/Paris'),'2026-12-28');
  assert.equal(dayKey(new Date('2026-11-09T02:00:00Z'),'America/Toronto'),'2026-11-08');
});
test('group capacity includes idempotent rejoin',() => {
  const group = {memberIDs:Array.from({length:8},(_,i)=>String(i))};
  assert.equal(canJoin(group,'outsider'),false); assert.equal(canJoin(group,'0'),true);
});
test('invitations store deterministic one-way hash, never plaintext',() => {
  assert.equal(invitationHash('secret').length,64); assert.equal(invitationHash('secret'),invitationHash('secret'));
  assert.notEqual(invitationHash('secret'),invitationHash('Secret'));
});
test('media MIME and size boundaries are enforced',() => {
  assert(mediaAllowed('video/mp4',30*1024*1024)); assert(!mediaAllowed('video/mp4',30*1024*1024+1));
  assert(!mediaAllowed('text/html',100)); assert(!mediaAllowed('image/jpeg',0)); assert(!mediaAllowed('image/jpeg',NaN));
});
