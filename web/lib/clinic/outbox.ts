'use client';

import { clinicSupabase, isOnline } from './supabase';
import { STORES, getAll, put, del, hasLocalDb } from './localdb';

// الطابور — اللي اتكتب ولسه ما وصلش السيرفر.
//
// Everything the doctor writes lands in IndexedDB first and is queued here.
// Nothing in the UI ever waits on this: the prescription is saved, printable
// and in the patient's file the instant it is written, and the flush is
// housekeeping that happens when the network allows.
//
// THE PROPERTY THAT MAKES THIS SAFE is that every RPC below is idempotent on
// an id the DEVICE generated. A reconnect that retries a request whose reply
// was lost produces one row, not two. See clinic.sync_prescription() — the
// second copy of a prescription in a patient's file is not a cosmetic bug.
//
// It is also why nothing here needs conflict resolution. These records are
// append-only and authored by exactly one device. The moment two devices could
// edit one row, this design would stop being sound and would need to be
// replaced rather than extended.

export type OutboxKind = 'patient' | 'encounter' | 'prescription';

export interface OutboxEntry {
  /** `${kind}:${id}` — re-queueing the same record REPLACES rather than piles up. */
  key: string;
  kind: OutboxKind;
  payload: Record<string, unknown>;
  queued_at: number;
  attempts: number;
  last_error?: string;
  /** A refusal no amount of retrying will fix. Surfaced to the user. */
  blocked?: boolean;
}

const RPC: Record<OutboxKind, string> = {
  patient: 'sync_patient',
  encounter: 'sync_encounter',
  prescription: 'sync_prescription',
};

/** Business refusals from the RPCs. Retrying these forever helps nobody. */
const PERMANENT = [
  'NOT_ALLOWED', 'NOT_YOUR_RX', 'NOT_YOURS', 'NO_PATIENT', 'BAD_PAYLOAD',
  'RX_PREFIX_MISMATCH', 'RX_EMPTY', 'RX_LINE_EMPTY', 'RX_ISSUED', 'NAME_REQUIRED',
];

const listeners = new Set<(n: number, blocked: number) => void>();
let flushing = false;

export function onOutboxChange(fn: (pending: number, blocked: number) => void): () => void {
  listeners.add(fn);
  void notify();
  return () => listeners.delete(fn);
}

async function notify(): Promise<void> {
  if (!hasLocalDb()) return;
  const all = await getAll<OutboxEntry>(STORES.outbox);
  const blocked = all.filter((e) => e.blocked).length;
  for (const fn of listeners) fn(all.length - blocked, blocked);
}

/**
 * Queue a record for the server. Returns immediately — it does NOT wait for
 * the network, which is the whole point.
 */
export async function queue(
  kind: OutboxKind,
  id: string,
  payload: Record<string, unknown>
): Promise<void> {
  if (!hasLocalDb()) return;
  const entry: OutboxEntry = {
    key: `${kind}:${id}`,
    kind,
    payload,
    queued_at: Date.now(),
    attempts: 0,
  };
  await put(STORES.outbox, entry);
  await notify();
  // Opportunistic: if there is a network right now this returns in a moment
  // and the badge never appears at all.
  void flush();
}

export async function pending(): Promise<OutboxEntry[]> {
  if (!hasLocalDb()) return [];
  return getAll<OutboxEntry>(STORES.outbox);
}

/**
 * Push everything queued, oldest first.
 *
 * ORDER IS NOT OPTIONAL. A prescription references a patient and an encounter;
 * sending it before them fails with NO_PATIENT. Oldest-first works because the
 * screens queue the patient before the encounter before the prescription — and
 * one failure stops the run rather than skipping ahead, so a stuck record
 * cannot let its dependants through in the wrong order.
 */
export async function flush(): Promise<{ sent: number; failed: number }> {
  if (!hasLocalDb() || flushing || !isOnline()) return { sent: 0, failed: 0 };

  flushing = true;
  let sent = 0;
  let failed = 0;

  try {
    const all = (await getAll<OutboxEntry>(STORES.outbox))
      .filter((e) => !e.blocked)
      .sort((a, b) => a.queued_at - b.queued_at);

    const sb = clinicSupabase();

    for (const entry of all) {
      try {
        const { error } = await sb.rpc(RPC[entry.kind], { p_payload: entry.payload });
        if (error) throw error;

        await del(STORES.outbox, entry.key);
        sent += 1;
      } catch (e) {
        failed += 1;
        const message = e instanceof Error ? e.message : String(e);
        const permanent = PERMANENT.some((m) => message.includes(m));

        await put(STORES.outbox, {
          ...entry,
          attempts: entry.attempts + 1,
          last_error: message,
          blocked: permanent,
        } satisfies OutboxEntry);

        // A transient failure means the network went away mid-run. Stop —
        // continuing would burn attempts on records whose turn has not come,
        // and would let a later record overtake the one that just failed.
        if (!permanent) break;
      }
    }
  } finally {
    flushing = false;
    await notify();
  }

  return { sent, failed };
}

/**
 * Give up on a record the server keeps refusing.
 *
 * Only ever called from a screen that has shown the doctor what is stuck and
 * why. A queue that silently discards a prescription would be worse than one
 * that never empties.
 */
export async function discard(key: string): Promise<void> {
  await del(STORES.outbox, key);
  await notify();
}

let wired = false;

/** Retry when the browser says the network is back, and periodically anyway. */
export function startAutoFlush(): () => void {
  if (typeof window === 'undefined' || wired) return () => {};
  wired = true;

  const go = () => void flush();
  window.addEventListener('online', go);
  // `online` is optimistic — it fires for a captive portal that has not
  // actually let us out yet, and it does not fire at all when a tunnel comes
  // back. The timer is what makes the queue eventually drain regardless.
  const timer = window.setInterval(go, 30_000);
  window.addEventListener('focus', go);

  return () => {
    window.removeEventListener('online', go);
    window.removeEventListener('focus', go);
    window.clearInterval(timer);
    wired = false;
  };
}
