'use client';

import { clinicSupabase } from './supabase';
import type { Patient, Prescription, ClinicStaff } from './types';

// النسخة الاحتياطية — ملف في إيد صاحب العيادة.
//
// Not a replacement for a real backup plan; the second half of one. A backup
// nobody has ever held is a backup nobody has ever verified, and Supabase's
// free plan has nothing restorable at all. See the note at the top of
// 20260812100007_clinic_export.sql.
//
// NO NEW DEPENDENCY. This repository has kept itself to Next, React and
// supabase-js, and a spreadsheet library to write two CSVs would be the fourth
// entry — for a format that is thirty lines of string handling.

export interface ExportCounts {
  patients: number;
  encounters: number;
  prescriptions: number;
  visits: number;
  last_export: string | null;
}

export interface ClinicExport {
  exported_at: string;
  schema_version: number;
  staff: ClinicStaff[];
  patients: Patient[];
  prescriptions: Prescription[];
  [key: string]: unknown;
}

export async function exportCounts(): Promise<ExportCounts | null> {
  const { data, error } = await clinicSupabase().rpc('export_counts');
  if (error) throw error;
  return (data as ExportCounts) ?? null;
}

export async function fetchExport(): Promise<ClinicExport> {
  const { data, error } = await clinicSupabase().rpc('export_all');
  if (error) throw error;
  if (!data) throw new Error('NOT_ALLOWED');
  return data as ClinicExport;
}

/** Hands the browser a file. Revokes the URL — these blobs are megabytes. */
function download(filename: string, blob: Blob): void {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

const stamp = () => new Date().toISOString().slice(0, 10);

/**
 * One CSV cell.
 *
 * The leading-character guard is not politeness — a value starting with =, +,
 * - or @ is executed as a FORMULA when the file is opened in Excel. A patient
 * whose notes begin with a minus sign is enough to trigger it, and a malicious
 * one is a known way to turn a spreadsheet into a command. Prefixing with a
 * quote makes Excel treat it as text.
 */
function cell(value: unknown): string {
  if (value === null || value === undefined) return '';
  let s = String(value);
  if (/^[=+\-@\t\r]/.test(s)) s = `'${s}`;
  return `"${s.replace(/"/g, '""')}"`;
}

function toCsv(headers: string[], rows: unknown[][]): Blob {
  const body = [headers.map(cell).join(','), ...rows.map((r) => r.map(cell).join(','))].join('\r\n');
  // ⚠ THE BOM IS LOAD-BEARING. Without it Excel on Windows reads a UTF-8 file
  // as the local codepage and every Arabic name in the export opens as
  // mojibake — a backup that is technically complete and practically
  // unreadable by the person it is for.
  return new Blob([`﻿${body}`], { type: 'text/csv;charset=utf-8' });
}

/** الكل، بالظبط — للاسترجاع. */
export async function downloadFullBackup(): Promise<ExportCounts> {
  const data = await fetchExport();
  download(
    `clinic-backup-${stamp()}.json`,
    new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' })
  );
  return {
    patients: data.patients.length,
    encounters: (data.encounters as unknown[] | undefined)?.length ?? 0,
    prescriptions: data.prescriptions.length,
    visits: (data.visits as unknown[] | undefined)?.length ?? 0,
    last_export: data.exported_at,
  };
}

/** المرضى — صف لكل مريض، بيتفتح في Excel. */
export async function downloadPatientsCsv(): Promise<number> {
  const data = await fetchExport();
  const rows = data.patients.map((p) => [
    p.file_no ?? '', p.full_name, p.phone ?? '', p.gender ?? '',
    p.birth_date ?? '', p.allergies_ar ?? '', p.chronic_ar ?? '',
    p.address_ar ?? '', p.notes_ar ?? '',
  ]);
  download(
    `clinic-patients-${stamp()}.csv`,
    toCsv(
      ['رقم الملف', 'الاسم', 'الموبايل', 'النوع', 'تاريخ الميلاد',
       'الحساسية', 'أمراض مزمنة', 'العنوان', 'ملاحظات'],
      rows
    )
  );
  return rows.length;
}

/**
 * الروشتات — صف لكل سطر دوا، مش لكل روشتة.
 *
 * One row per LINE, deliberately: a spreadsheet is something people filter and
 * sort, and "every time we prescribed Augmentin" is the question they will
 * actually ask. A row per prescription with the drugs mashed into one cell
 * cannot answer it.
 */
export async function downloadPrescriptionsCsv(): Promise<number> {
  const data = await fetchExport();
  const byId = new Map(data.patients.map((p) => [p.id, p]));
  const staffById = new Map(data.staff.map((s) => [s.id, s]));

  const rows: unknown[][] = [];
  for (const rx of data.prescriptions) {
    const patient = byId.get(rx.patient_id);
    for (const item of rx.items ?? []) {
      rows.push([
        rx.written_at?.slice(0, 10) ?? '',
        rx.rx_no,
        staffById.get(rx.doctor_id)?.display_name ?? '',
        patient?.file_no ?? '',
        patient?.full_name ?? '',
        item.drug_name,
        item.strength ?? '', item.form_ar ?? '',
        item.dose_ar ?? '', item.frequency_ar ?? '', item.duration_ar ?? '',
        item.notes_ar ?? '',
        rx.status,
        rx.amended_from ? 'نسخة معدّلة' : '',
      ]);
    }
  }

  download(
    `clinic-prescriptions-${stamp()}.csv`,
    toCsv(
      ['التاريخ', 'رقم الروشتة', 'الدكتور', 'رقم الملف', 'المريض',
       'الدوا', 'التركيز', 'الشكل', 'الجرعة', 'كام مرة', 'المدة',
       'ملاحظات', 'الحالة', 'تعديل'],
      rows
    )
  );
  return rows.length;
}
