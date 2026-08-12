'use client';

import { foldArabic } from '../arabic.js';
import { rankDrugs } from './drugSearch.js';
import { clinicSupabase } from './supabase';
import { getAll, putMany, getMeta, setMeta, META, STORES, hasLocalDb } from './localdb';
import type { Drug, LabTest } from './types';

// البحث عن الدواء — أول حرف يطلّع النتيجة، والنت مالوش دخل.
//
// The catalogue is downloaded WHOLE and searched HERE, in memory, on the
// device. Both halves of that are load-bearing:
//
//   * On the device, because the doctor types a letter and expects the list
//     now. A round trip per keystroke is slow on a good connection and absent
//     on a bad one.
//   * Whole, because a partial index would still need the server for the miss,
//     and "the drug you wanted is the one that needs the internet" is the
//     worst possible failure mode for this box.
//
// A few thousand rows of five short fields is a few hundred kilobytes. It is
// downloaded once and then only the delta.
//
// THE FOLDING IS SHARED, NOT REIMPLEMENTED. `name_key` is a generated column
// running public.fold_arabic(); the term below is folded by foldArabic() from
// web/lib/arabic.js. tools/schema-check/verify.mjs asserts those two agree —
// without it, a drug stored as "سيتال" would be unfindable by someone typing
// "سيتأل", and nobody would ever discover why.

let memDrugs: Drug[] | null = null;
let memTests: LabTest[] | null = null;
let memUsage: Record<string, number> = {};

export interface CatalogState {
  drugs: number;
  tests: number;
  syncedAt: string | null;
}

/**
 * Loads the cached catalogue into memory. Idempotent and cheap after the first
 * call — the search box calls it on mount and then never thinks about it.
 */
export async function loadCatalog(): Promise<CatalogState> {
  if (!hasLocalDb()) return { drugs: 0, tests: 0, syncedAt: null };

  if (memDrugs === null) {
    memDrugs = (await getAll<Drug>(STORES.drugs)).filter((d) => d.is_active);
    memTests = (await getAll<LabTest>(STORES.tests)).filter((t) => t.is_active);
    memUsage = (await getMeta<Record<string, number>>('drug_usage')) ?? {};
  }
  return {
    drugs: memDrugs.length,
    tests: memTests?.length ?? 0,
    syncedAt: (await getMeta<string>(META.catalogSyncedAt)) ?? null,
  };
}

/**
 * Pulls whatever changed since the last sync.
 *
 * Withdrawn drugs arrive as `is_active: false` rather than as an absence — a
 * device that only ever hears about additions would go on offering a drug the
 * clinic has pulled, forever.
 */
export async function syncCatalog(force = false): Promise<CatalogState> {
  if (!hasLocalDb()) return { drugs: 0, tests: 0, syncedAt: null };

  const since = force ? null : ((await getMeta<string>(META.catalogSyncedAt)) ?? null);

  const { data, error } = await clinicSupabase().rpc('drug_catalog', { p_since: since });
  if (error) throw error;

  const payload = data as {
    version: number; now: string;
    drugs: Drug[]; tests: LabTest[]; usage: Record<string, number>;
  } | null;
  if (!payload) throw new Error('NOT_ALLOWED');

  await putMany(STORES.drugs, payload.drugs);
  await putMany(STORES.tests, payload.tests);
  await setMeta('drug_usage', payload.usage ?? {});
  await setMeta(META.catalogVersion, payload.version);
  await setMeta(META.catalogSyncedAt, payload.now);

  // Force the next loadCatalog() to re-read rather than patching the in-memory
  // copy by hand. Reconciling a delta in two places is how the two drift.
  memDrugs = null;
  return loadCatalog();
}

// ---------------------------------------------------------------------------
//  البحث
// ---------------------------------------------------------------------------

export interface DrugHit extends Drug {
  /** Lower sorts first. Exposed so the picker can group visually if it wants. */
  rank: number;
}

/**
 * Ranked, synchronous, no await anywhere on the hot path.
 *
 * The ranking itself lives in ./drugSearch.js — authored as plain JavaScript so
 * that tools/schema-check/clinic.mjs can import this exact code and run it
 * against the real seeded catalogue. A search this feature depends on, tested
 * only by using the app, is a search nobody is testing.
 */
export function searchDrugs(term: string, limit = 12): DrugHit[] {
  const all = memDrugs;
  if (!all || all.length === 0) return [];
  return rankDrugs(all, memUsage, term, limit) as DrugHit[];
}

export function searchTests(term: string, limit = 12): LabTest[] {
  const all = memTests;
  if (!all) return [];
  const q = foldArabic(term).trim();
  if (q === '') return all.slice(0, limit);
  return all
    .filter((t) => t.name_key.includes(q) || (t.name_en ?? '').toLowerCase().includes(q))
    .slice(0, limit);
}

/**
 * A drug the doctor typed that is not in the catalogue.
 *
 * Goes to the server, so it needs a connection — but the prescription line
 * itself does NOT: the line stores `drug_name` as a snapshot, so a free-typed
 * name prints and files perfectly well with `drug_id` null. This only adds it
 * to the catalogue for next time, and failing quietly is the right behaviour.
 */
export async function addDrug(
  tradeName: string,
  genericAr?: string,
  formAr = '',
  strength = ''
): Promise<string | null> {
  try {
    const { data, error } = await clinicSupabase().rpc('add_drug', {
      p_trade_name: tradeName,
      p_generic_ar: genericAr ?? null,
      p_form_ar: formAr,
      p_strength: strength,
    });
    if (error) throw error;
    await syncCatalog();
    return data as string;
  } catch {
    return null;
  }
}

/** Called on sign-out so the next person at this desk starts from nothing. */
export function forgetCatalog(): void {
  memDrugs = null;
  memTests = null;
  memUsage = {};
}
