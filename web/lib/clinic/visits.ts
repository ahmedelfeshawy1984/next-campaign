'use client';

import { clinicSupabase } from './supabase';
import { cachePatients } from './patients';
import type {
  QueueRow, HomeCounts, VisitStatus, PayMethod,
  DoctorReportRow, ClinicSettings, ClinicStaff, Patient,
} from './types';

// الطابور والمواعيد والفلوس — كلها بتحتاج نت.
//
// Deliberately NOT part of the offline path. A queue is a shared, live view of
// what several people are doing at once; a stale copy of it is worse than an
// honest "مفيش نت". What has to survive an outage is the doctor writing and
// printing, and that is rx.ts.
//
// The one thing this does do offline is leave behind whoever was in today's
// queue, cached as patients — so an outage mid-session still finds the people
// physically in the waiting room.

export async function todayQueue(): Promise<QueueRow[]> {
  const { data, error } = await clinicSupabase().rpc('today_queue');
  if (error) throw error;
  const rows = (data ?? []) as QueueRow[];

  await cachePatients(rows.map((r) => ({
    id: r.patient_id,
    file_no: r.file_no,
    full_name: r.full_name,
    phone: r.phone,
    gender: null, birth_date: null, address_ar: null,
    allergies_ar: null, chronic_ar: null, notes_ar: null,
  } satisfies Patient)));

  return rows;
}

export async function homeCounts(): Promise<HomeCounts | null> {
  const { data, error } = await clinicSupabase().rpc('clinic_home');
  if (error) throw error;
  return (data as HomeCounts) ?? null;
}

export async function bookVisit(
  patientId: string,
  doctorId: string | null,
  when: string | null = null
): Promise<string> {
  const { data, error } = await clinicSupabase().rpc('book_visit', {
    p_patient: patientId,
    p_doctor: doctorId,
    p_when: when,
  });
  if (error) throw error;
  return data as string;
}

export async function setVisitStatus(id: string, status: VisitStatus): Promise<void> {
  const { error } = await clinicSupabase().rpc('set_visit_status', {
    p_id: id,
    p_status: status,
  });
  if (error) throw error;
}

export async function takePayment(
  visitId: string,
  amount: number,
  method: PayMethod = 'cash',
  note?: string
): Promise<void> {
  const { error } = await clinicSupabase().rpc('take_payment', {
    p_visit: visitId,
    p_amount: amount,
    p_method: method,
    p_note: note ?? null,
  });
  if (error) throw error;
}

export interface DaySheet {
  day: string;
  visits: number;
  due: number | string;
  collected: number | string;
  by_method: Record<string, number | string>;
}

export async function daySheet(day?: string): Promise<DaySheet | null> {
  const { data, error } = await clinicSupabase().rpc('day_sheet', { p_day: day ?? null });
  if (error) throw error;
  return (data as DaySheet) ?? null;
}

export async function reportByDoctor(from: string, to: string): Promise<DoctorReportRow[]> {
  const { data, error } = await clinicSupabase().rpc('report_by_doctor', {
    p_from: from,
    p_to: to,
  });
  if (error) throw error;
  return (data ?? []) as DoctorReportRow[];
}

export interface RxReportRow {
  rx_id: string;
  rx_no: string;
  written_at: string;
  status: string;
  doctor_id: string;
  doctor_name: string;
  patient_id: string;
  file_no: number | null;
  patient_name: string;
  diagnosis_ar: string | null;
  amended_from: string | null;
  items: { drug_name: string; dose_ar: string | null; frequency_ar: string | null;
           duration_ar: string | null }[];
}

export async function reportPrescriptions(
  from: string,
  to: string,
  doctorId?: string | null
): Promise<RxReportRow[]> {
  const { data, error } = await clinicSupabase().rpc('report_prescriptions', {
    p_from: from,
    p_to: to,
    p_doctor: doctorId ?? null,
  });
  if (error) throw error;
  return (data ?? []) as RxReportRow[];
}

export async function clinicSettings(): Promise<ClinicSettings | null> {
  const { data, error } = await clinicSupabase()
    .from('settings').select('*').limit(1).maybeSingle();
  if (error) throw error;
  return (data as ClinicSettings) ?? null;
}

/** The doctors a visit can be assigned to. Reception needs this to book. */
export async function clinicians(): Promise<ClinicStaff[]> {
  const { data, error } = await clinicSupabase()
    .from('staff')
    .select('*')
    .in('role', ['doctor', 'director'])
    .eq('is_active', true)
    .order('display_name');
  if (error) throw error;
  return (data ?? []) as ClinicStaff[];
}

export const VISIT_STATUS_LABEL: Record<VisitStatus, string> = {
  booked: 'محجوز',
  waiting: 'في الانتظار',
  in_room: 'جوّه',
  done: 'خلص',
  no_show: 'ما جاش',
  cancelled: 'ملغي',
};

export const PAY_METHOD_LABEL: Record<PayMethod, string> = {
  cash: 'كاش',
  instapay: 'إنستاباي',
  card: 'فيزا',
  other: 'غير كده',
};
