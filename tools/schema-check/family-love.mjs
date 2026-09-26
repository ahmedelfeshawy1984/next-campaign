// فحوصات Family Love — مستقل تمامًا عن verify.mjs (مشروع Supabase منفصل،
// معندوش حاجة مشتركة مع الشوب/العيادة يستاهل يتفحص مع بعض)، بس بنفس أدوات
// stub.mjs (auth stub، asUser/asAnon/expectBlocked) وبنفس نظام العدّ والتقرير.
//
// بيثبت الحاجات اللي لو غلطت هتبقى خطر حقيقي ومش هحس بيه:
//   ١. anon مالوش أي مقبض على الباب خالص.
//   ٢. عيلتين مختلفتين ما يشوفوش بيانات بعض (fl_my_circle عزل حقيقي).
//   ٣. تقدّم الطفل (current_station_index) محمي — جهاز طفل تاني ميقدرش يقدّمه.
//   ٤. كود الربط وكود دعوة فرد العيلة single-use، وكود دعوة الفرد بيضمّ لنفس
//      الدائرة مش دائرة جديدة.
//   ٥. قاعدة التكرار في JS (recurrence.js) متطابقة مع fl_task_occurs_on() في SQL.
//
// بورت ودليل بيانات مختلفين عن verify.mjs عمدًا — الاتنين يقدروا يشتغلوا مع
// بعض من غير تعارض، وبيتصل بقاعدة postgres الافتراضية مباشرة (زي verify.mjs)
// بدل ما يعمل قاعدة بيانات باسم مخصص — معندوش داعي هنا، المشروع كله معزول
// أصلاً في نسخة Postgres مستقلة.
//
// G:\dev-tools\node\node.exe tools/schema-check/family-love.mjs
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import EmbeddedPostgresMod from 'embedded-postgres';

import { AUTH_STUB, clearDataDir, makeChecker, asUser, expectBlockedAnon } from './stub.mjs';
import { taskOccursOn } from '../../web/lib/family-love/recurrence.js';

const here = dirname(fileURLToPath(import.meta.url));
const EmbeddedPostgres = EmbeddedPostgresMod.default ?? EmbeddedPostgresMod;
const MIG = resolve(here, '../../supabase/family-love/migrations');
const SEED = resolve(here, '../../supabase/family-love/seed.sql');
const PORT = 54998;

const { results, check } = makeChecker();

const dataDir = join(here, 'pgdata-family-love');
clearDataDir(dataDir);

const pg = new EmbeddedPostgres({
  databaseDir: dataDir,
  user: 'postgres',
  password: 'postgres',
  port: PORT,
  persistent: false,
  initdbFlags: ['--encoding=UTF8', '--locale=C'],
});

console.log('initialising postgres (family-love, port ' + PORT + ')...');
await pg.initialise();
await pg.start();

const { Client } = await import('pg');
const client = new Client({ host: 'localhost', port: PORT, user: 'postgres', password: 'postgres', database: 'postgres' });
await client.connect();

async function one(sql, params = []) {
  return (await client.query(sql, params)).rows[0];
}

// زي asUser بتاعة stub.mjs بالظبط، لكن بتعمل commit مش rollback — لازمة هنا
// لأي خطوة بتنشئ صف (كود ربط، دعوة فرد) لازم يفضل موجود عشان خطوة بعدها
// (خارج الترانزاكشن دي) تستبدله.
async function asUserCommitted(uid, fn) {
  await client.query('begin');
  await client.query('set local role authenticated');
  await client.query(`set local "request.jwt.claim.sub" = '${uid}'`);
  const result = await fn();
  await client.query('commit');
  return result;
}

const A1 = 'a0000000-0000-0000-0000-000000000001'; // جهاز الأب/الأم — دائرة A
const A2 = 'a0000000-0000-0000-0000-000000000002'; // جهاز الطفل — دائرة A
const B2 = 'b0000000-0000-0000-0000-000000000002'; // جهاز الطفل — دائرة B

try {
  await client.query(AUTH_STUB);

  for (const file of readdirSync(MIG).sort()) {
    await client.query(readFileSync(join(MIG, file), 'utf8'));
  }
  check('all family-love migrations apply to an empty database', true);

  await client.query(readFileSync(SEED, 'utf8'));
  const templateCount = await one(`select count(*)::int n from public.message_templates`);
  check('message_templates seeded with system defaults', templateCount.n > 0, `${templateCount.n} rows`);

  // ---- دائرتين مختلفتين، معمولين مباشرة (الهارنس ده مش بيشغّل طبقة الـ API) --

  const accountA = await one(`insert into public.accounts (phone, full_name) values ('01011111111','أم A') returning id`);
  const circA = await one(
    `insert into public.family_circles (owner_account_id, name) values ($1, 'دائرة A') returning id`,
    [accountA.id]
  );
  await client.query(`insert into public.family_members (family_circle_id, account_id, is_owner) values ($1,$2,true)`, [
    circA.id,
    accountA.id,
  ]);
  // fl_upsert_parent_account() بيعمل الصف ده تلقائيًا في الاستخدام الحقيقي —
  // هنا بنعمله يدوي لأن الفكستشرز دي معمولة مباشرة، مش عن طريق تسجيل الدخول.
  await client.query(
    `insert into public.subscriptions (family_circle_id, trial_ends_at) values ($1, now() + interval '45 days')`,
    [circA.id]
  );
  const childA = await one(
    `insert into public.child_profiles (family_circle_id, display_name) values ($1,'يوسف') returning id`,
    [circA.id]
  );
  const taskA = await one(
    `insert into public.tasks (family_circle_id, child_profile_id, title, recurrence_rule, created_by)
     values ($1,$2,'رحلة المدرسة','{"kind":"daily"}'::jsonb,$3) returning id`,
    [circA.id, childA.id, accountA.id]
  );
  await client.query(
    `insert into public.stations (task_id, order_index, title) values ($1,0,'خرجت من البيت'), ($1,1,'وصلت الباص'), ($1,2,'وصلت المدرسة')`,
    [taskA.id]
  );
  await client.query(`insert into public.device_sessions (id, kind, account_id, token_hash) values ($1,'parent',$2,'x')`, [
    A1,
    accountA.id,
  ]);
  await client.query(`insert into public.device_sessions (id, kind, child_profile_id, token_hash) values ($1,'child',$2,'x')`, [
    A2,
    childA.id,
  ]);

  const accountB = await one(`insert into public.accounts (phone, full_name) values ('01022222222','أم B') returning id`);
  const circB = await one(`insert into public.family_circles (owner_account_id, name) values ($1,'دائرة B') returning id`, [
    accountB.id,
  ]);
  const childB = await one(
    `insert into public.child_profiles (family_circle_id, display_name) values ($1,'سارة') returning id`,
    [circB.id]
  );
  await client.query(`insert into public.device_sessions (id, kind, child_profile_id, token_hash) values ($1,'child',$2,'x')`, [
    B2,
    childB.id,
  ]);

  // ---- ١. anon مالوش أي حق قراءة خالص ---------------------------------------

  await expectBlockedAnon(client, check, `select * from public.tasks`, 'anon cannot read tasks');
  await expectBlockedAnon(client, check, `select * from public.device_sessions`, 'anon cannot read device_sessions');
  await expectBlockedAnon(client, check, `select * from public.child_profiles`, 'anon cannot read child_profiles');

  // ---- ٢. عزل تام بين الدوائر -------------------------------------------------

  await asUser(client, A1, async () => {
    const mine = await one(`select public.fl_my_circle() c`);
    check('parent A resolves to circle A', mine.c === circA.id);
    const leak = await one(`select count(*)::int n from public.family_circles where id = $1`, [circB.id]);
    check('parent A cannot see circle B at all', leak.n === 0);
  });

  // ---- ٣. لوحة اليوم + حماية تقدّم المحطة -----------------------------------
  //
  // كل الخطوات دي في ترانزاكشن واحدة نتحكم فيها يدويًا (مش asUser، اللي بترجع
  // rollback دايمًا آخر كل استدعاء — وده كان بيمسح صف task_occurrences اللي
  // اتعمل بمجرد ما البلوك يقفل، فالخطوة اللي بعدها بتلاقي الصف مش موجود).
  // فحص "جهاز تاني ميقدرش يقدّم" بيحصل جوه savepoint عشان نرجع لنفس الحالة
  // من غير ما نضيّع تقدّم الطفل A.

  await client.query('begin');
  await client.query('set local role authenticated');
  await client.query(`set local "request.jwt.claim.sub" = '${A2}'`);

  const board = await one(`select public.fl_today_board() b`);
  const tasks = board.b;
  check("child A gets exactly today's one task with 3 stations", tasks.length === 1 && tasks[0].stations.length === 3);
  const occurrenceId = tasks[0].occurrence_id;

  const advanced = await one(`select * from public.fl_advance_station($1)`, [occurrenceId]);
  check('advancing once moves current_station_index to 1', advanced.current_station_index === 1);
  check('status becomes in_progress after the first station', advanced.status === 'in_progress');

  await client.query('savepoint sp_ownership');
  await client.query('set local role authenticated');
  await client.query(`set local "request.jwt.claim.sub" = '${B2}'`);
  let ownershipBlocked = false;
  try {
    await client.query(`select public.fl_advance_station($1)`, [occurrenceId]);
  } catch {
    ownershipBlocked = true;
  }
  check("child B cannot advance family A's occurrence (real ownership check, not just row invisibility)", ownershipBlocked);
  await client.query('rollback to savepoint sp_ownership');
  await client.query('set local role authenticated');
  await client.query(`set local "request.jwt.claim.sub" = '${A2}'`);

  await client.query(`select public.fl_advance_station($1)`, [occurrenceId]);
  const done = await one(`select * from public.fl_advance_station($1)`, [occurrenceId]);
  check(
    'advancing past the last station lands on done, not overflow',
    done.status === 'done' && done.current_station_index === 3
  );

  await client.query('commit');

  // ---- ٤. ملكية الموقع اللحظي -------------------------------------------------

  await client.query('begin');
  await client.query('set local role authenticated');
  await client.query(`set local "request.jwt.claim.sub" = '${A2}'`);
  await client.query(
    `insert into public.location_pings (family_circle_id, child_profile_id, lat, lng) values ($1,$2,30.05,31.23)`,
    [circA.id, childA.id]
  );

  await client.query('savepoint sp_location');
  await client.query('set local role authenticated');
  await client.query(`set local "request.jwt.claim.sub" = '${B2}'`);
  let locationBlocked = false;
  try {
    await client.query(
      `insert into public.location_pings (family_circle_id, child_profile_id, lat, lng) values ($1,$2,1,1)`,
      [circA.id, childA.id]
    );
  } catch {
    locationBlocked = true;
  }
  check('child B cannot send a location ping for child A', locationBlocked);
  await client.query('rollback to savepoint sp_location');
  await client.query('commit');

  // ---- ٥. كود الربط: استخدام واحد بس ------------------------------------------

  const pairing = await asUserCommitted(A1, () =>
    one(`select * from public.fl_create_pairing_token($1)`, [childA.id])
  );
  const redeemed = await one(`select * from public.fl_redeem_pairing_token($1)`, [pairing.code]);
  check('pairing code redeems to the right child', redeemed.child_profile_id === childA.id);

  const newChildDevice = await one(
    `insert into public.device_sessions (kind, child_profile_id, token_hash) values ('child',$1,'y') returning id`,
    [childA.id]
  );
  await client.query(`select public.fl_mark_pairing_token_redeemed($1, $2)`, [pairing.id, newChildDevice.id]);

  let secondPairingRedeemFailed = false;
  try {
    await client.query(`select public.fl_redeem_pairing_token($1)`, [pairing.code]);
  } catch {
    secondPairingRedeemFailed = true;
  }
  check('a pairing code cannot be redeemed twice', secondPairingRedeemFailed);

  // ---- ٦. دعوة فرد العيلة: بتضم لنفس الدائرة، استخدام واحد بس -----------------

  const invite = await asUserCommitted(A1, () => one(`select * from public.fl_create_member_invite('spouse')`));
  const inviteCode = invite.code;
  const joined = await one(`select * from public.fl_redeem_member_invite($1, '01099999999', 'الزوج')`, [inviteCode]);
  check("redeeming a member invite joins the INVITER's circle, not a new one", joined.family_circle_id === circA.id);

  let secondInviteRedeemFailed = false;
  try {
    await client.query(`select public.fl_redeem_member_invite($1, '01088888888', 'حد تاني')`, [inviteCode]);
  } catch {
    secondInviteRedeemFailed = true;
  }
  check('a member invite cannot be redeemed twice', secondInviteRedeemFailed);

  // ---- ٧. الاشتراك/التجربة -----------------------------------------------------

  await asUser(client, A1, async () => {
    const ent = await one(`select public.fl_my_entitlement() e`);
    check(
      'a fresh circle starts in trial with a future trial_ends_at',
      ent.e.status === 'trialing' && new Date(ent.e.trial_ends_at) > new Date()
    );
  });

  // ---- ٨. recurrence.js متطابق مع fl_task_occurs_on() ---------------------------

  const cases = [
    [{ kind: 'daily' }, '2026-09-27'],
    [{ kind: 'weekly', weekdays: [0, 3, 5] }, '2026-09-27'], // Sunday
    [{ kind: 'weekly', weekdays: [0, 3, 5] }, '2026-09-28'], // Monday
    [{ kind: 'monthly', day_of_month: 1 }, '2026-10-01'],
    [{ kind: 'monthly', day_of_month: 1 }, '2026-10-02'],
    [{ kind: 'once', date: '2026-10-05' }, '2026-10-05'],
    [{ kind: 'once', date: '2026-10-05' }, '2026-10-06'],
  ];
  let allAgree = true;
  for (const [rule, isoDate] of cases) {
    const jsResult = taskOccursOn(rule, new Date(`${isoDate}T00:00:00Z`));
    const sqlResult = await one(`select public.fl_task_occurs_on($1::jsonb, $2::date) v`, [JSON.stringify(rule), isoDate]);
    if (jsResult !== sqlResult.v) {
      allAgree = false;
      console.log(`  mismatch: ${JSON.stringify(rule)} on ${isoDate} -> js=${jsResult} sql=${sqlResult.v}`);
    }
  }
  check('recurrence.js (taskOccursOn) agrees with fl_task_occurs_on() on every case', allAgree, `${cases.length} cases`);
} catch (e) {
  check('the harness ran to the end', false, `${e.message}`.slice(0, 300));
  console.error(e);
} finally {
  const failed = results.filter((r) => !r.ok);
  console.log(`\n${results.length - failed.length}/${results.length} passed`);
  if (failed.length) {
    console.log('\nFAILED:');
    for (const f of failed) console.log(`  - ${f.name}${f.detail ? ' -> ' + f.detail : ''}`);
  }
  await client.end().catch(() => {});
  await pg.stop().catch(() => {});
  process.exit(failed.length ? 1 : 0);
}
