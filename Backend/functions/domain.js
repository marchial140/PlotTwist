'use strict';
const crypto = require('node:crypto');
function dayKey(date, timezone) {
  const parts = new Intl.DateTimeFormat('en-CA', {timeZone:timezone, year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(date);
  const get = type => parts.find(p => p.type === type).value;
  return `${get('year')}-${get('month')}-${get('day')}`;
}
function weekKey(date, timezone) {
  const day = new Date(`${dayKey(date,timezone)}T12:00:00Z`);
  day.setUTCDate(day.getUTCDate() - (day.getUTCDay()+6)%7);
  return day.toISOString().slice(0,10);
}
function invitationHash(code) { return crypto.createHash('sha256').update(code).digest('hex'); }
function canJoin(group, uid) { return group.memberIDs.includes(uid) || group.memberIDs.length < 8; }
function mediaAllowed(type,size) { return Number.isFinite(size) && size > 0 && ((type==='image/jpeg' && size<=8*1024*1024) || (type==='video/mp4' && size<=30*1024*1024)); }
module.exports = {dayKey,weekKey,invitationHash,canJoin,mediaAllowed};
