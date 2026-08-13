// فحوصات العيادة.
//
// A separate file from verify.mjs because the clinic is a separate schema with
// a separate threat model, and because verify.mjs was already long enough that
// finding anything in it was work.
//
// The assertions here are the ones that would be catastrophic to get wrong and
// invisible if we did:
//
//   1. anon cannot reach ANYTHING in the clinic schema — proven by enumerating
//      the schema rather than by listing tables, so a table added next year is
//      covered without anyone remembering to add it here.
//   2. Reception cannot read a diagnosis or a prescription.
//   3. A doctor can READ a colleague's prescription and cannot WRITE to it —
//      the exact shape of the shared-file decision.
//   4. An issued prescription is frozen.
//   5. sync_prescription() is IDEMPOTENT. This is the one that protects
//      against a duplicate prescription in a patient's file when the internet
//      comes back, and it is the reason offline writing is safe at all.
//   6. The Arabic folding and phone normalisation the offline search depends on
//      agree with the SQL that generated the stored keys.

import { foldArabic } from '../../web/lib/arabic.js';
import { normalizePhone } from '../../web/lib/phone.js';
import { rankDrugs } from '../../web/lib/clinic/drugSearch.js';

const DOCTOR_A   = '44444444-4444-4444-4444-444444444444';
const DOCTOR_B   = '55555555-5555-5555-5555-555555555555';
const RECEPTION  = '66666666-6666-6666-6666-666666666666';
const DIRECTOR   = '77777777-7777-7777-7777-777777777777';

export async function clinicChecks(ctx) {
  const { client, check, one, asUser, expectBlocked, expectBlockedAnon } = ctx;

  // ---- staff ---------------------------------------------------------------

  // Straight into auth.users, the way verify.mjs seeds its own users: the
  // handle_new_user() trigger mirrors the profile, and clinic.staff hangs off
  // that. Going through clinic.create_staff() would need a director to already
  // exist, which is what the migration's own seed does and is tested below.
  await client.query(
    `insert into auth.users (id, email, raw_user_meta_data) values
       ($1, 'doca@clinic.test',  '{"role":"customer","full_name":"دكتور أ","phone":"01111111101"}'::jsonb),
       ($2, 'docb@clinic.test',  '{"role":"customer","full_name":"دكتور ب","phone":"01111111102"}'::jsonb),
       ($3, 'recep@clinic.test', '{"role":"customer","full_name":"استقبال","phone":"01111111103"}'::jsonb),
       ($4, 'dir@clinic.test',   '{"role":"customer","full_name":"ديريكتور","phone":"01111111104"}'::jsonb)`,
    [DOCTOR_A, DOCTOR_B, RECEPTION, DIRECTOR]
  );
  await client.query(
    `insert into clinic.staff (id, role, display_name, rx_prefix) values
       ($1, 'doctor',    'د. أ',      'دأ'),
       ($2, 'doctor',    'د. ب',      'دب'),
       ($3, 'reception', 'الاستقبال',  null),
       ($4, 'director',  'الديريكتور', 'دد')`,
    [DOCTOR_A, DOCTOR_B, RECEPTION, DIRECTOR]
  );

  const seeded = await one(
    `select count(*)::int n from clinic.staff where role = 'director'`);
  check(
    'the migration seeds a first director, and the test one joins them',
    seeded.n === 2,
    `${seeded.n} directors`
  );

  // Reception has no rx_prefix and must not need one; a clinician without one
  // would number prescriptions into a collision the first time they go offline.
  await expectBlocked(
    client, check, DIRECTOR,
    `insert into clinic.staff (id, role, display_name, rx_prefix)
     values ('88888888-8888-8888-8888-888888888888', 'doctor', 'بلا بادئة', null)`,
    'a doctor cannot be created without a prescription prefix'
  );

  // ---- anon reaches NOTHING -------------------------------------------------

  // Enumerated, not listed. A hand-written list of tables silently stops
  // covering the table somebody adds next year, and reports a clean run.
  const tables = (
    await client.query(
      `select table_name from information_schema.tables
        where table_schema = 'clinic' and table_type = 'BASE TABLE'
        order by table_name`)
  ).rows.map((r) => r.table_name);

  check('clinic schema has tables to check', tables.length >= 15, `${tables.length} tables`);

  let leaked = [];
  for (const t of tables) {
    try {
      await client.query('begin');
      await client.query('set local role anon');
      await client.query(`select * from clinic.${t} limit 1`);
      leaked.push(t);
    } catch {
      /* refused, which is the point */
    } finally {
      await client.query('rollback');
    }
  }
  check(
    'anon cannot read a single table in the clinic schema',
    leaked.length === 0,
    leaked.length ? `LEAKED: ${leaked.join(', ')}` : `${tables.length} tables all refused`
  );

  const anonFns = (
    await client.query(
      `select p.proname from pg_proc p
         join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'clinic'
          and has_function_privilege('anon', p.oid, 'EXECUTE')`)
  ).rows.map((r) => r.proname);
  check(
    'anon cannot execute a single function in the clinic schema',
    anonFns.length === 0,
    anonFns.length ? `LEAKED: ${anonFns.join(', ')}` : 'none'
  );

  await expectBlockedAnon(
    client, check, 'select clinic.is_staff()',
    'anon cannot even ask whether it is clinic staff');

  // ---- a patient, and the folding the offline search depends on -------------

  let patientId;
  await asUserCommitted(client, RECEPTION, async () => {
    const r = await client.query(
      `select clinic.sync_patient($1::jsonb) p`,
      [JSON.stringify({
        id: '99999999-9999-9999-9999-999999999999',
        full_name: 'أحمد عبد الله',
        phone: '٠١٠١٢٣٤٥٦٧٨',
        allergies_ar: 'بنسلين',
      })]
    );
    patientId = r.rows[0].p.id;   // node-postgres parses jsonb for us
  });

  const stored = await one(
    'select name_key, phone, file_no from clinic.patients where id = $1', [patientId]);

  // The three-way agreement the whole offline drug search rests on. The device
  // folds a search term with foldArabic(); the database folded the stored key
  // with public.fold_arabic(). If they ever diverge, "احمد" stops finding
  // "أحمد" and nobody discovers why.
  check(
    'clinic.patients.name_key folds exactly the way web/lib/arabic.js does',
    stored.name_key === foldArabic('أحمد عبد الله'),
    `${stored.name_key} vs ${foldArabic('أحمد عبد الله')}`
  );
  check(
    'a patient phone typed in Arabic-Indic digits normalises like web/lib/phone.js',
    stored.phone === normalizePhone('٠١٠١٢٣٤٥٦٧٨'),
    `${stored.phone}`
  );
  check(
    'the SERVER assigns the file number, not the device',
    // Number(), not Number.isInteger(): file_no is a bigint, and node-postgres
    // hands those back as STRINGS to avoid silently losing precision past 2^53.
    Number(stored.file_no) > 0,
    `file ${stored.file_no}`
  );

  await asUser(client, DOCTOR_A, async () => {
    const r = await client.query(
      `select count(*)::int n from clinic.search_patients('احمد')`);
    check(
      'searching the unaccented spelling finds the accented patient',
      r.rows[0].n === 1,
      `${r.rows[0].n} hits`
    );
  });

  // ---- reception is walled off from the clinical record ---------------------

  let rxA;
  await asUserCommitted(client, DOCTOR_A, async () => {
    const r = await client.query(
      `select clinic.sync_prescription($1::jsonb) p`,
      [JSON.stringify({
        id: 'aaaaaaaa-0000-0000-0000-000000000001',
        patient_id: patientId,
        rx_no: 'دأ-260812-a001',
        status: 'issued',
        items: [{ drug_name: 'Augmentin', dose_ar: 'قرص', frequency_ar: 'مرتين يوميًا' }],
      })]
    );
    rxA = r.rows[0].p;
  });
  check('a doctor can issue a prescription', rxA.status === 'issued', rxA.rx_no);

  await asUser(client, RECEPTION, async () => {
    const rx = await client.query('select count(*)::int n from clinic.prescriptions');
    const enc = await client.query('select count(*)::int n from clinic.encounters');
    const pat = await client.query('select count(*)::int n from clinic.patients');
    check('reception sees no prescriptions at all', rx.rows[0].n === 0);
    check('reception sees no encounters at all', enc.rows[0].n === 0);
    // …and this is the control: the walls are around the CLINICAL tables, not
    // around reception's ability to do their job. Without this assertion the
    // two above would pass just as well on a totally broken install.
    check('reception CAN still see patients', pat.rows[0].n > 0, `${pat.rows[0].n}`);
  });

  await expectBlocked(
    client, check, RECEPTION,
    `select clinic.sync_prescription('{"id":"aaaaaaaa-0000-0000-0000-00000000000f",
      "patient_id":"99999999-9999-9999-9999-999999999999","rx_no":"x-1","items":[]}'::jsonb)`,
    'reception cannot write a prescription');

  // ---- the shared file: read yes, write no ---------------------------------

  await asUser(client, DOCTOR_B, async () => {
    const r = await client.query(
      'select count(*)::int n from clinic.prescriptions where doctor_id = $1', [DOCTOR_A]);
    check(
      "a doctor CAN read a colleague's prescription — the shared file",
      r.rows[0].n === 1
    );
  });

  await expectBlocked(
    client, check, DOCTOR_B,
    `select clinic.sync_prescription($$
       {"id":"aaaaaaaa-0000-0000-0000-000000000001",
        "patient_id":"99999999-9999-9999-9999-999999999999",
        "rx_no":"دب-260812-a001","items":[{"drug_name":"X"}]}$$::jsonb)`,
    "a doctor cannot overwrite a colleague's prescription");

  await expectBlocked(
    client, check, DOCTOR_B,
    `select clinic.issue_prescription('aaaaaaaa-0000-0000-0000-000000000001')`,
    "a doctor cannot issue a colleague's prescription");

  // The numbering guard. Without it a bug in one device could file
  // prescriptions inside another doctor's series, and the director's report
  // would be quietly wrong rather than loudly broken.
  await expectBlocked(
    client, check, DOCTOR_B,
    `select clinic.sync_prescription($$
       {"id":"aaaaaaaa-0000-0000-0000-000000000009",
        "patient_id":"99999999-9999-9999-9999-999999999999",
        "rx_no":"دأ-260812-a099","items":[{"drug_name":"X"}]}$$::jsonb)`,
    "a doctor cannot file under another doctor's prescription prefix");

  // Authorship is taken from auth.uid(), never from the payload. A device that
  // could name its own author could put words in a colleague's mouth.
  await asUserCommitted(client, DOCTOR_B, async () => {
    await client.query(
      `select clinic.sync_prescription($1::jsonb)`,
      [JSON.stringify({
        id: 'bbbbbbbb-0000-0000-0000-000000000001',
        patient_id: patientId,
        doctor_id: DOCTOR_A,                    // ← a lie, and it must not stick
        rx_no: 'دب-260812-a001',
        status: 'issued',
        items: [{ drug_name: 'Panadol' }],
      })]
    );
  });
  const authored = await one(
    `select doctor_id from clinic.prescriptions where id = 'bbbbbbbb-0000-0000-0000-000000000001'`);
  check(
    'doctor_id comes from the session, not from the payload',
    authored.doctor_id === DOCTOR_B,
    authored.doctor_id
  );

  // ---- an issued prescription is frozen ------------------------------------

  await expectBlocked(
    client, check, DOCTOR_A,
    `update clinic.prescriptions set rx_no = 'tampered'
      where id = 'aaaaaaaa-0000-0000-0000-000000000001'`,
    'an issued prescription cannot be edited by its own author');

  // ⚠ ASSERTED BY COUNTING, NOT BY EXPECTING A THROW, and the difference is the
  //   trap stub.mjs warns about: a missing GRANT raises 42501, but an RLS
  //   policy that simply does not match FILTERS — the DELETE touches zero rows
  //   and reports success. Asserting "it throws" here would fail against a
  //   perfectly secure database, and worse, the reverse mistake elsewhere
  //   passes for the wrong reason and keeps passing after the policy is
  //   deleted. What matters is that the line is still there afterwards.
  await asUserCommitted(client, DOCTOR_A, async () => {
    await client.query(
      `delete from clinic.prescription_items
        where rx_id = 'aaaaaaaa-0000-0000-0000-000000000001'`);
  });
  const survived = await one(
    `select count(*)::int n from clinic.prescription_items
      where rx_id = 'aaaaaaaa-0000-0000-0000-000000000001'`);
  check(
    'a line cannot be removed from an issued prescription',
    survived.n === 1,
    `${survived.n} lines left`
  );

  // ---- IDEMPOTENCY — the assertion the offline design rests on -------------

  await asUserCommitted(client, DOCTOR_A, async () => {
    const again = await client.query(
      `select clinic.sync_prescription($1::jsonb) p`,
      [JSON.stringify({
        id: 'aaaaaaaa-0000-0000-0000-000000000001',
        patient_id: patientId,
        rx_no: 'دأ-260812-a001',
        status: 'issued',
        items: [{ drug_name: 'Augmentin', dose_ar: 'قرص', frequency_ar: 'مرتين يوميًا' }],
      })]
    );
    const reply = again.rows[0].p;
    check(
      're-sending an issued prescription reports it as a duplicate rather than failing',
      reply.duplicate === true
    );
  });

  const copies = await one(
    `select count(*)::int n from clinic.prescriptions where rx_no = 'دأ-260812-a001'`);
  check(
    'sending the SAME prescription twice leaves ONE row — the outbox can retry safely',
    copies.n === 1,
    `${copies.n} rows`
  );
  const lines = await one(
    `select count(*)::int n from clinic.prescription_items
      where rx_id = 'aaaaaaaa-0000-0000-0000-000000000001'`);
  check('and it does not duplicate the lines either', lines.n === 1, `${lines.n} lines`);

  // ---- amendment: a new row, the original untouched ------------------------

  let amended;
  await asUserCommitted(client, DOCTOR_B, async () => {
    const r = await client.query(
      `select clinic.amend_prescription('aaaaaaaa-0000-0000-0000-000000000001', 'الجرعة غلط') id`);
    amended = r.rows[0].id;
  });

  const original = await one(
    `select rx_no, status from clinic.prescriptions
      where id = 'aaaaaaaa-0000-0000-0000-000000000001'`);
  check(
    'amending leaves the original prescription exactly as it was',
    original.rx_no === 'دأ-260812-a001' && original.status === 'issued'
  );
  const child = await one(
    'select doctor_id, amended_from, amend_reason from clinic.prescriptions where id = $1',
    [amended]);
  check(
    'the amendment is a new prescription in the AMENDING doctor\'s name',
    child.doctor_id === DOCTOR_B && child.amended_from === 'aaaaaaaa-0000-0000-0000-000000000001',
    child.amend_reason
  );

  await expectBlocked(
    client, check, DOCTOR_A,
    `select clinic.amend_prescription('aaaaaaaa-0000-0000-0000-000000000001', '')`,
    'an amendment without a reason is refused');

  // ---- the director's report -----------------------------------------------

  // Also counted rather than thrown. `where clinic.is_director()` inside a
  // `language sql` function is the same shape public.admin_staff() uses: a
  // non-director gets an empty result set, not an error. Empty is the security
  // property; the exception was never the point.
  await asUser(client, DOCTOR_A, async () => {
    const r = await client.query(
      `select count(*)::int n from clinic.report_prescriptions(
         current_date - 1, current_date + 1, null)`);
    check(
      "a doctor gets nothing from the director's prescription report",
      r.rows[0].n === 0,
      `${r.rows[0].n} rows`
    );
  });

  await asUser(client, DIRECTOR, async () => {
    const byDoc = await client.query(
      `select doctor_name, prescriptions from clinic.report_by_doctor(
         current_date - 1, current_date + 1) where prescriptions > 0`);
    check(
      'the director sees which doctor wrote how many prescriptions',
      byDoc.rowCount === 2,
      byDoc.rows.map((r) => `${r.doctor_name}:${r.prescriptions}`).join(' ')
    );

    const rxs = await client.query(
      `select rx_no, doctor_name, patient_name, jsonb_array_length(items) n
         from clinic.report_prescriptions(current_date - 1, current_date + 1, null)`);
    check(
      'and sees who each one was for, with the drugs on it',
      rxs.rowCount === 3 && rxs.rows.every((r) => r.patient_name && r.n >= 1),
      rxs.rows.map((r) => `${r.rx_no}→${r.doctor_name}`).join(' ')
    );
  });

  await asUser(client, RECEPTION, async () => {
    const r = await client.query(
      `select count(*)::int n from clinic.report_by_doctor(
         current_date - 1, current_date + 1)`);
    check('reception gets nothing from the doctor report', r.rows[0].n === 0);
  });

  // ---- the drug catalogue --------------------------------------------------

  const drugs = await one('select count(*)::int n from clinic.drugs');
  check('the drug catalogue is seeded', drugs.n > 50, `${drugs.n} drugs`);

  const folded = await one(
    `select name_key from clinic.drugs where trade_name = 'Augmentin' limit 1`);
  check(
    'a drug name_key folds the way the offline search folds its term',
    folded.name_key.includes(foldArabic('أموكسيسيللين')),
    folded.name_key.slice(0, 60)
  );

  await asUser(client, DOCTOR_A, async () => {
    const full = await client.query('select clinic.drug_catalog(null) c');
    const payload = full.rows[0].c;
    check(
      'the whole catalogue can be pulled for the device in one call',
      payload.drugs.length > 50 && payload.tests.length > 10,
      `${payload.drugs.length} drugs, ${payload.tests.length} tests`
    );

    const delta = await client.query('select clinic.drug_catalog(now()) c');
    check(
      'and a delta since now returns almost nothing — the daily sync is cheap',
      delta.rows[0].c.drugs.length === 0
    );
  });

  const bumped = await one('select drug_catalog_version v from clinic.settings');
  check(
    'the catalogue version moves when the catalogue does',
    Number(bumped.v) > 1,
    `v${bumped.v}`
  );

  // ---- البحث نفسه، على الكتالوج الحقيقي -------------------------------------
  //
  // The headline promise of this whole feature is "الدكتور بيكتب أول حرف والدوا
  // بيطلع", offline. The pieces of that are: the seeded catalogue, the folding
  // that name_key was generated with, and the ranking in
  // web/lib/clinic/drugSearch.js — which is imported HERE, the same file the
  // browser runs, and pointed at the rows Postgres actually holds.
  //
  // Testing the ranking against a hand-written fixture would prove the sort is
  // a sort. This proves a doctor typing "aug" gets Augmentin.
  const catalogue = (
    await client.query('select id, trade_name, name_key from clinic.drugs where is_active')
  ).rows;

  const cases = [
    ['aug',   'Augmentin',   'three Latin letters find the brand'],
    ['أوجمنتين', 'Augmentin', 'the Arabic spelling of the brand finds it too'],
    ['بار',   'Panadol',     'an Arabic generic prefix finds a product that carries it'],
    ['كونكور', 'Concor',     'an Arabic brand spelling finds the Latin trade name'],
    ['فلاجيل', 'Flagyl',     'and another'],
  ];

  for (const [typed, expected, why] of cases) {
    const hits = rankDrugs(catalogue, {}, typed, 12);
    const names = hits.map((h) => h.trade_name);
    check(
      `typing "${typed}" finds ${expected} — ${why}`,
      names.includes(expected),
      names.slice(0, 4).join(', ') || 'no hits'
    );
  }

  // One letter. The literal promise.
  const oneLetter = rankDrugs(catalogue, {}, 'ب', 12);
  check(
    'a SINGLE Arabic letter already returns candidates',
    oneLetter.length > 0,
    `${oneLetter.length} hits, first: ${oneLetter[0]?.trade_name}`
  );

  // Rank 0 must beat rank 2: a brand that STARTS with the term outranks one
  // that merely contains it somewhere in its generic name.
  const ranked = rankDrugs(catalogue, {}, 'pan', 12);
  check(
    'a trade-name prefix match outranks a mid-word one',
    ranked.length > 0 && ranked[0].trade_name.toLowerCase().startsWith('pan'),
    ranked.slice(0, 3).map((h) => `${h.trade_name}(${h.rank})`).join(' ')
  );

  // The doctor's own habits float to the top within a rank.
  const twoBrufen = catalogue.filter((d) => d.trade_name === 'Brufen');
  if (twoBrufen.length >= 2) {
    const usage = { [twoBrufen[1].id]: 40 };
    const withHabit = rankDrugs(catalogue, usage, 'brufen', 5);
    check(
      "the drug this doctor actually prescribes comes first among equals",
      withHabit[0].id === twoBrufen[1].id,
      withHabit.map((h) => h.id.slice(0, 4)).join(' ')
    );
  }

  // A term that matches nothing must return nothing rather than everything —
  // a search that silently degrades to "here is the catalogue" is worse than
  // an empty list, because the doctor picks from it.
  check(
    'a nonsense term returns no hits at all',
    rankDrugs(catalogue, {}, 'زقزقزق', 12).length === 0
  );

  // ---- النسخة الاحتياطية ----------------------------------------------------
  //
  // A bulk read of every patient record in the clinic — the most sensitive
  // single operation the system can perform, and therefore the one whose
  // access check is worth asserting rather than assuming.

  await expectBlocked(
    client, check, DOCTOR_A, 'select clinic.export_all()',
    'a doctor cannot export the whole clinic');
  await expectBlocked(
    client, check, RECEPTION, 'select clinic.export_all()',
    'reception cannot export the whole clinic');

  await asUserCommitted(client, DIRECTOR, async () => {
    const r = await client.query('select clinic.export_all() e');
    const dump = r.rows[0].e;

    check(
      'the director gets an export containing the patients and the prescriptions',
      dump.patients.length >= 1 && dump.prescriptions.length >= 3,
      `${dump.patients.length} patients, ${dump.prescriptions.length} prescriptions`
    );

    // The lines have to travel WITH their prescription. A backup read by a
    // human under pressure must not require reassembling a prescription from
    // a second array somewhere else in the file.
    check(
      'every exported prescription carries its own drug lines',
      dump.prescriptions.every((p) => Array.isArray(p.items) && p.items.length >= 1),
      dump.prescriptions.map((p) => `${p.rx_no}:${p.items?.length}`).join(' ')
    );

    check(
      'the export carries a schema version, so a future restorer knows what it is reading',
      dump.schema_version === 1 && !!dump.exported_at
    );

    // Credentials live in auth.users, which this schema never touches. Worth
    // an assertion: a backup file gets e-mailed, copied to a flash drive and
    // left on a desk.
    const serialised = JSON.stringify(dump);
    check(
      'the export contains no password hash of any kind',
      !/encrypted_password|\$2[aby]\$/.test(serialised),
      `${Math.round(serialised.length / 1024)} kB`
    );
  });

  // Asking for the export is itself recorded. An export is the one action that
  // can walk out of the building with every patient in it.
  const exportAudit = await one(
    `select count(*)::int n from clinic.audit_events
      where action = 'exported_everything'`);
  check(
    'exporting the clinic is written to the audit log',
    exportAudit.n === 1,
    `${exportAudit.n} events`
  );

  await asUser(client, RECEPTION, async () => {
    const r = await client.query('select clinic.export_counts() c');
    check('reception gets nothing from export_counts()', r.rows[0].c === null);
  });

  // ---- the audit log cannot be edited by the audited ------------------------

  await expectBlocked(
    client, check, DIRECTOR,
    `update clinic.audit_events set action = 'nothing to see' where id > 0`,
    'not even the director can rewrite the audit log');
  await expectBlocked(
    client, check, DIRECTOR,
    'delete from clinic.audit_events where id > 0',
    'and nobody can delete from it');
}

// verify.mjs keeps its own copy of this inside a closure; the clinic checks
// need the committed variant too, for the same reason — a status that is rolled
// back before the next assertion makes the next assertion pass for the wrong
// reason.
async function asUserCommitted(client, uid, fn) {
  await client.query('set role authenticated');
  await client.query(`set "request.jwt.claim.sub" = '${uid}'`);
  try {
    return await fn();
  } finally {
    await client.query('reset "request.jwt.claim.sub"');
    await client.query('reset role');
  }
}
