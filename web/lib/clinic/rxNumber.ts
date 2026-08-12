'use client';

import { getMeta, setMeta, bumpCounter, META } from './localdb';

// رقم الروشتة — بيتولّد على الجهاز.
//
// A sequence in the database would be the obvious choice and it is the wrong
// one here: a sequence needs the server, and the entire requirement is that
// the prescription prints when the server is unreachable. So the number is
// assembled locally out of three parts that cannot collide:
//
//   د1  -  260812  -  a047
//   │        │         ││
//   │        │         │└─ counter, resets every day
//   │        │         └── this DEVICE, one base-36 character
//   │        └──────────── the date, yyMMdd
//   └───────────────────── this DOCTOR, clinic.staff.rx_prefix, unique
//
// The device character is the part that is easy to leave out and expensive to
// miss. Doctor + day + counter alone is unique only while one doctor writes
// from one device; the day they open the clinic laptop AND their phone while
// the internet is down, both count 001 and one of the two prescriptions is
// rejected on sync with a paper copy already in a patient's hand.
//
// The whole string is what the SQL side checks against the doctor's prefix
// (`rx_no like prefix || '-%'` in clinic.sync_prescription), which is why the
// device character sits after a dash rather than glued onto the prefix.

const DEVICE_KEY = 'device_tag';

/** One base-36 character, minted once per browser profile and then reused. */
export async function deviceTag(): Promise<string> {
  const existing = await getMeta<string>(DEVICE_KEY);
  if (existing) return existing;

  const tag = Math.floor(Math.random() * 36).toString(36);
  await setMeta(DEVICE_KEY, tag);
  return tag;
}

/** yyMMdd in LOCAL time — the clinic's day, not UTC's. */
export function rxDayKey(when = new Date()): string {
  const yy = String(when.getFullYear() % 100).padStart(2, '0');
  const mm = String(when.getMonth() + 1).padStart(2, '0');
  const dd = String(when.getDate()).padStart(2, '0');
  return `${yy}${mm}${dd}`;
}

/**
 * The next prescription number for this doctor, on this device, today.
 *
 * Never reaches the network. Returns something like `د1-260812-a047`.
 */
export async function nextRxNo(prefix: string, when = new Date()): Promise<string> {
  const day = rxDayKey(when);
  const tag = await deviceTag();
  const n = await bumpCounter(META.rxCounter(prefix, day));
  return `${prefix}-${day}-${tag}${String(n).padStart(3, '0')}`;
}
