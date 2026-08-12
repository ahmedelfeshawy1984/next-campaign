'use client';

import { foldArabic } from '../arabic.js';
import { normalizePhone } from '../phone.js';
import { clinicSupabase, isOnline } from './supabase';
import { STORES, getAll, get, put, putMany, hasLocalDb } from './localdb';
import { queue } from './outbox';
import type { Patient, PatientSearchRow, PatientFile } from './types';

// المرضى — الجهاز الأول، والسيرفر بعده.
//
// Every read here answers from IndexedDB when the network is not there, and
// tops the cache up when it is. The cache is deliberately NOT the whole
// patient list: today's queue and whoever was opened recently, and no more.
// A full copy of every file the clinic has ever opened, sitting unencrypted on
// a laptop that can be stolen, is a much larger loss than the inconvenience of
// not seeing an old patient's history during an outage.

const RECENT_LIMIT = 400;

/** Remember a patient locally so they are there when the network is not. */
export async function cachePatients(rows: Patient[]): Promise<void> {
  if (!hasLocalDb() || rows.length === 0) return;
  await putMany(STORES.patients, rows.map((p) => ({ ...p, cached_at: Date.now() })));
}

/**
 * Search by Arabic name, by phone, or by file number.
 *
 * Online the server answers, because it holds every patient. Offline the same
 * question is asked of the local copy, folded by the SAME function the
 * server's `name_key` column was generated with — see web/lib/arabic.js and
 * the harness assertion that keeps the two honest.
 */
export async function searchPatients(term: string): Promise<PatientSearchRow[]> {
  if (isOnline()) {
    try {
      const { data, error } = await clinicSupabase().rpc('search_patients', {
        p_term: term,
        p_limit: 30,
      });
      if (error) throw error;
      const rows = (data ?? []) as PatientSearchRow[];
      await cachePatients(rows as unknown as Patient[]);
      return rows;
    } catch {
      // fall through to the local copy — an outage mid-search should narrow
      // the results, not empty the screen
    }
  }
  return searchLocal(term);
}

async function searchLocal(term: string): Promise<PatientSearchRow[]> {
  if (!hasLocalDb()) return [];
  const all = await getAll<Patient>(STORES.patients);

  const q = foldArabic(term).trim();
  const digits = normalizePhone(term);
  const fileNo = term.replace(/[^0-9]/g, '');

  return all
    .filter((p) => {
      if (q === '' && digits === '' ) return true;
      if (q !== '' && foldArabic(p.full_name).includes(q)) return true;
      if (digits !== '' && (p.phone ?? '').startsWith(digits)) return true;
      if (fileNo !== '' && String(p.file_no ?? '') === fileNo) return true;
      return false;
    })
    .slice(0, RECENT_LIMIT)
    .map((p) => ({
      id: p.id,
      file_no: p.file_no,
      full_name: p.full_name,
      phone: p.phone,
      gender: p.gender,
      birth_date: p.birth_date,
      allergies_ar: p.allergies_ar,
      chronic_ar: p.chronic_ar,
      last_visit: null,
    }));
}

export async function getPatient(id: string): Promise<Patient | null> {
  if (hasLocalDb()) {
    const local = await get<Patient>(STORES.patients, id);
    if (local && !isOnline()) return local;
  }
  try {
    const { data, error } = await clinicSupabase()
      .from('patients').select('*').eq('id', id).maybeSingle();
    if (error) throw error;
    if (data) await cachePatients([data as Patient]);
    return (data as Patient) ?? null;
  } catch {
    return hasLocalDb() ? ((await get<Patient>(STORES.patients, id)) ?? null) : null;
  }
}

/**
 * Register or update a patient.
 *
 * Writes locally and queues. The file number comes back from the server later
 * — see clinic.sync_patient() for why the device is not allowed to invent one.
 */
export async function savePatient(patch: Partial<Patient> & { full_name: string }): Promise<Patient> {
  const id = patch.id ?? crypto.randomUUID();
  const row: Patient = {
    id,
    file_no: patch.file_no ?? null,
    full_name: patch.full_name.trim(),
    phone: patch.phone ? normalizePhone(patch.phone) : null,
    gender: patch.gender ?? null,
    birth_date: patch.birth_date ?? null,
    address_ar: patch.address_ar ?? null,
    allergies_ar: patch.allergies_ar ?? null,
    chronic_ar: patch.chronic_ar ?? null,
    notes_ar: patch.notes_ar ?? null,
  };

  if (hasLocalDb()) await put(STORES.patients, row);
  await queue('patient', id, row as unknown as Record<string, unknown>);
  return row;
}

/**
 * The whole file in one call — visits, encounters, prescriptions, each with
 * the name of the doctor who wrote it.
 *
 * Needs the network: this is the shared clinic-wide history, and the point of
 * it is seeing what a COLLEAGUE prescribed, which by definition is not on this
 * device. Offline the screen says so and still lets the doctor write.
 */
export async function patientFile(id: string): Promise<PatientFile | null> {
  const { data, error } = await clinicSupabase().rpc('patient_file', { p_patient: id });
  if (error) throw error;
  return (data as PatientFile) ?? null;
}

/** ٣٤ سنة / ٧ شهور — what a doctor writes at the top of a note. */
export function ageLabel(birthDate: string | null): string {
  if (!birthDate) return '—';
  const b = new Date(birthDate);
  if (Number.isNaN(b.getTime())) return '—';

  const now = new Date();
  let months = (now.getFullYear() - b.getFullYear()) * 12 + (now.getMonth() - b.getMonth());
  if (now.getDate() < b.getDate()) months -= 1;
  if (months < 0) return '—';

  if (months < 24) return `${months} شهر`;
  return `${Math.floor(months / 12)} سنة`;
}
