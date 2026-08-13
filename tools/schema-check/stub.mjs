import { rmSync } from 'node:fs';

// The parts of Supabase the migrations lean on, recreated well enough to run
// the real SQL locally.
//
// The single most important line here is `create extension pgcrypto with
// schema extensions`. On Supabase, crypt() and gen_salt() live in `extensions`;
// installing them into `public` — the default — is what let the sibling
// project ship account creation that passed every local test and failed on the
// customer's database with "function gen_salt(unknown) does not exist". A
// harness that does not model that difference is a harness that certifies the
// bug.
export const AUTH_STUB = `
-- Guarded, because ROLES ARE CLUSTER-WIDE while everything else here is
-- per-database. The standalone-bundle check installs into a second database on
-- the same server and would otherwise die on "role anon already exists" —
-- which reads like a broken bundle rather than a role that is, correctly,
-- already there.
do $stub$ begin
  create role anon nologin noinherit;
exception when duplicate_object then null; end $stub$;
do $stub$ begin
  create role authenticated nologin noinherit;
exception when duplicate_object then null; end $stub$;
do $stub$ begin
  create role service_role nologin noinherit bypassrls;
exception when duplicate_object then null; end $stub$;

grant usage on schema public to anon, authenticated, service_role;

create schema extensions;
grant usage on schema extensions to anon, authenticated, service_role;
create extension if not exists pgcrypto with schema extensions;
set search_path to public, extensions;

-- Supabase grants table privileges to these roles by default; RLS is the gate,
-- not the grant.
alter default privileges in schema public grant all on tables     to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions  to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences  to anon, authenticated, service_role;

create schema auth;
grant usage on schema auth to authenticated, service_role;

create table auth.users (
  id uuid primary key,
  instance_id uuid,
  aud text,
  role text,
  email text unique,
  encrypted_password text,
  email_confirmed_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz,
  raw_app_meta_data jsonb,
  raw_user_meta_data jsonb,
  -- The token columns a direct insert leaves NULL. Present so that
  -- fix_auth_user_tokens() has something to find; its guarded loop is exactly
  -- what makes it survive a Supabase version with a different column set.
  confirmation_token text,
  recovery_token text,
  email_change text,
  email_change_token_new text,
  reauthentication_token text
);

create table auth.identities (
  id uuid primary key,
  provider_id text,
  user_id uuid references auth.users(id) on delete cascade,
  identity_data jsonb,
  provider text,
  last_sign_in_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz
);

create or replace function auth.uid() returns uuid
language sql stable as $fn$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$fn$;

-- storage, so the storage migration runs here too. An excluded migration is
-- one nobody is checking.
create schema storage;
grant usage on schema storage to anon, authenticated, service_role;
create table storage.buckets (
  id text primary key, name text, public boolean,
  file_size_limit bigint, allowed_mime_types text[]
);
create table storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text, name text, owner uuid, created_at timestamptz default now()
);
alter table storage.objects enable row level security;
create or replace function storage.foldername(name text) returns text[]
language sql immutable as $fn$ select string_to_array(name, '/') $fn$;
`;

/// embedded-postgres is told the database is throwaway, but on Windows the
/// directory routinely survives — a killed run, a failed check that exits
/// non-zero, a file still held open by the postgres process as it goes down.
/// The next run then dies on "directory exists but is not empty", which looks
/// like a broken harness rather than leftover rubbish. Clear it first.
export function clearDataDir(dir) {
  rmSync(dir, { recursive: true, force: true });
}

export function makeChecker() {
  const results = [];
  const check = (name, ok, detail = '') => {
    results.push({ name, ok, detail });
    console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  -> ' + detail : ''}`);
  };
  return { results, check };
}

/// Runs a callback as a signed-in user, then rolls back so the next check
/// starts from the same database.
export async function asUser(client, uid, fn) {
  await client.query('begin');
  try {
    await client.query('set local role authenticated');
    await client.query(`set local "request.jwt.claim.sub" = '${uid}'`);
    return await fn();
  } finally {
    await client.query('rollback');
  }
}

/// Runs a callback as the anonymous key — the role every customer of this app
/// actually uses, because browsing needs no account. Rolls back afterwards.
export async function asAnon(client, fn) {
  await client.query('begin');
  try {
    await client.query('set local role anon');
    return await fn();
  } finally {
    await client.query('rollback');
  }
}

/// Asserts an anonymous statement is refused.
///
/// Note the two shapes a refusal takes, and why both are checked separately in
/// verify.mjs: a missing GRANT raises (42501), while an RLS policy that simply
/// does not match FILTERS — an UPDATE returns zero rows and no error. Asserting
/// "it throws" for the second case passes for the wrong reason, and keeps
/// passing on the day the policy is deleted.
export async function expectBlockedAnon(client, check, sql, label, params = []) {
  await client.query('begin');
  try {
    await client.query('set local role anon');
    await client.query(sql, params);
    check(label, false, 'expected a refusal, the statement succeeded');
  } catch (e) {
    check(label, true, `blocked (${e.code || String(e.message).slice(0, 70)})`);
  } finally {
    await client.query('rollback');
  }
}

/// Asserts that a statement is refused. A boundary nobody tests is a boundary
/// that quietly stops existing the first time a policy is edited.
export async function expectBlocked(client, check, uid, sql, label, params = []) {
  await client.query('begin');
  try {
    await client.query('set local role authenticated');
    await client.query(`set local "request.jwt.claim.sub" = '${uid}'`);
    await client.query(sql, params);
    check(label, false, 'expected a refusal, the statement succeeded');
  } catch (e) {
    check(label, true, `blocked (${e.code || String(e.message).slice(0, 70)})`);
  } finally {
    await client.query('rollback');
  }
}
