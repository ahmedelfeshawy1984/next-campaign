'use client';

import { clinicSupabase, isOnline } from './supabase';
import { STORES, get, put, hasLocalDb } from './localdb';
import { queue } from './outbox';
import { nextRxNo } from './rxNumber';
import type { Prescription, RxItem, Encounter, ClinicStaff } from './types';

// الروشتة — بتتكتب وبتتطبع من الجهاز.
//
// Nothing on this path awaits the network. The doctor writes, the record is
// saved locally, the print page reads it back from IndexedDB, and the outbox
// gets it to the server whenever it can. That ordering is the requirement, not
// an optimisation: the patient is standing there.

/** A blank prescription, numbered locally. Never touches the network. */
export async function newPrescription(
  patientId: string,
  doctor: ClinicStaff,
  encounterId: string | null = null
): Promise<Prescription> {
  if (!doctor.rx_prefix) throw new Error('RX_PREFIX_MISMATCH');

  const rx: Prescription = {
    id: crypto.randomUUID(),
    patient_id: patientId,
    encounter_id: encounterId,
    doctor_id: doctor.id,
    rx_no: await nextRxNo(doctor.rx_prefix),
    status: 'draft',
    issued_at: null,
    printed_count: 0,
    amended_from: null,
    amend_reason: null,
    written_at: new Date().toISOString(),
    doctor_name: doctor.display_name,
    items: [],
  };

  if (hasLocalDb()) await put(STORES.prescriptions, rx);
  return rx;
}

/** Save a draft locally. Queued too, so a lost device does not lose the work. */
export async function saveDraft(rx: Prescription): Promise<void> {
  if (hasLocalDb()) await put(STORES.prescriptions, rx);
  await queue('prescription', rx.id, toPayload(rx));
}

/**
 * إصدار — the point of no return.
 *
 * Marked issued LOCALLY first so the print page can render immediately, then
 * queued. clinic.sync_prescription() applies the same transition server-side
 * and refuses any later edit; the local copy is not the authority, it is the
 * copy that is available right now.
 */
export async function issuePrescription(rx: Prescription): Promise<Prescription> {
  if (rx.items.length === 0) throw new Error('RX_EMPTY');
  if (rx.items.some((i) => !i.drug_name.trim())) throw new Error('RX_LINE_EMPTY');

  const issued: Prescription = {
    ...rx,
    status: 'issued',
    issued_at: new Date().toISOString(),
  };

  if (hasLocalDb()) await put(STORES.prescriptions, issued);
  await queue('prescription', issued.id, toPayload(issued));
  return issued;
}

/**
 * Read one back — for the print page, and for reopening a draft.
 *
 * Local FIRST, unconditionally. The print page must not depend on a round trip
 * that may not complete, and the local copy of a prescription this device
 * wrote is by construction the same record the server holds.
 */
export async function getPrescription(id: string): Promise<Prescription | null> {
  if (hasLocalDb()) {
    const local = await get<Prescription>(STORES.prescriptions, id);
    if (local) return local;
  }
  if (!isOnline()) return null;

  const sb = clinicSupabase();
  const { data, error } = await sb
    .from('prescriptions')
    .select('*, prescription_items(*)')
    .eq('id', id)
    .maybeSingle();
  if (error) throw error;
  if (!data) return null;

  const row = data as Prescription & { prescription_items: RxItem[] };
  const rx: Prescription = {
    ...row,
    items: [...(row.prescription_items ?? [])].sort(
      (a, b) => (a.line_no ?? 0) - (b.line_no ?? 0)
    ),
  };
  if (hasLocalDb()) await put(STORES.prescriptions, rx);
  return rx;
}

/** Count a printed copy. Best-effort — a failure here must not block printing. */
export async function markPrinted(id: string): Promise<void> {
  try {
    await clinicSupabase().rpc('mark_printed', { p_id: id });
  } catch {
    /* offline, or already counted. Neither is worth interrupting a print for. */
  }
}

/**
 * نسخة معدّلة — a NEW prescription pointing back at this one.
 *
 * Server-side, and therefore online-only, which is fine: amending requires the
 * original in front of you and is never the thing being done when the network
 * has just died.
 */
export async function amendPrescription(id: string, reason: string): Promise<string> {
  const { data, error } = await clinicSupabase().rpc('amend_prescription', {
    p_id: id,
    p_reason: reason,
  });
  if (error) throw error;
  return data as string;
}

function toPayload(rx: Prescription): Record<string, unknown> {
  return {
    id: rx.id,
    patient_id: rx.patient_id,
    encounter_id: rx.encounter_id,
    rx_no: rx.rx_no,
    status: rx.status,
    written_at: rx.written_at,
    items: rx.items.map((i) => ({
      drug_id: i.drug_id,
      drug_name: i.drug_name,
      form_ar: i.form_ar,
      strength: i.strength,
      dose_ar: i.dose_ar,
      frequency_ar: i.frequency_ar,
      duration_ar: i.duration_ar,
      route_ar: i.route_ar,
      notes_ar: i.notes_ar,
    })),
  };
}

// ------------------------------------------------------------- الكشف ----

export function newEncounter(patientId: string, doctorId: string, visitId: string | null = null): Encounter {
  return {
    id: crypto.randomUUID(),
    patient_id: patientId,
    visit_id: visitId,
    doctor_id: doctorId,
    temp_c: null, pulse: null, bp_sys: null, bp_dia: null,
    weight_kg: null, height_cm: null,
    complaint_ar: null, history_ar: null, exam_ar: null,
    diagnosis_ar: null, plan_ar: null, next_visit_on: null,
    status: 'draft',
  };
}

export async function saveEncounter(e: Encounter): Promise<void> {
  if (hasLocalDb()) await put(STORES.encounters, e);
  await queue('encounter', e.id, e as unknown as Record<string, unknown>);
}

export async function getEncounter(id: string): Promise<Encounter | null> {
  if (!hasLocalDb()) return null;
  return (await get<Encounter>(STORES.encounters, id)) ?? null;
}
