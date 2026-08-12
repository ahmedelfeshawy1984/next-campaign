'use client';

// قاعدة بيانات على الجهاز — مش كاش.
//
// THE DISTINCTION MATTERS. A cache is something you fall back on when the
// network is slow. This is where the doctor's writing LANDS FIRST, every time,
// online or not, and the print page reads from here rather than from the
// server. That is the only arrangement in which "the internet dropped" and
// "the prescription printed" are both true.
//
//   الدكتور بيكتب  →  IndexedDB  →  الطباعة بتقرأ من هنا
//                        ↓
//                     outbox  →  السيرفر أول ما النت يرجع
//
// Hand-rolled over the raw IndexedDB API rather than pulling in `idb`. The
// surface used here is five calls wide, this repository has kept its
// dependency list to Next, React and supabase-js, and a wrapper is not worth
// the fourth entry.
//
// ⚠ INDEXEDDB IS NOT ENCRYPTED. Patient names, diagnoses and prescriptions sit
//   on the clinic's laptop in the clear. That is the unavoidable price of
//   working with no network, and it is why docs/العيادة.md makes full-disk
//   encryption and a device PIN a setup step rather than a suggestion.

const DB_NAME = 'clinic';
const DB_VERSION = 1;

export const STORES = {
  meta: 'meta',
  drugs: 'drugs',
  tests: 'tests',
  patients: 'patients',
  encounters: 'encounters',
  prescriptions: 'prescriptions',
  outbox: 'outbox',
} as const;

export type StoreName = (typeof STORES)[keyof typeof STORES];

let dbPromise: Promise<IDBDatabase> | null = null;

/** Is there an IndexedDB here at all? Private windows and old browsers say no. */
export function hasLocalDb(): boolean {
  return typeof indexedDB !== 'undefined';
}

function openDb(): Promise<IDBDatabase> {
  if (dbPromise) return dbPromise;

  dbPromise = new Promise<IDBDatabase>((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);

    req.onupgradeneeded = () => {
      const db = req.result;
      // `meta` is keyed by an explicit string rather than a keyPath: it holds
      // single scalars (catalogue version, last sync time, today's counter)
      // that have no natural object shape.
      if (!db.objectStoreNames.contains(STORES.meta)) db.createObjectStore(STORES.meta);

      for (const name of [STORES.drugs, STORES.tests, STORES.patients,
                          STORES.encounters, STORES.prescriptions] as const) {
        if (!db.objectStoreNames.contains(name)) {
          db.createObjectStore(name, { keyPath: 'id' });
        }
      }

      if (!db.objectStoreNames.contains(STORES.outbox)) {
        const out = db.createObjectStore(STORES.outbox, { keyPath: 'key' });
        // Flush order is the order things were written. A prescription that
        // references an encounter must not overtake it.
        out.createIndex('queued_at', 'queued_at');
      }
    };

    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error ?? new Error('IndexedDB refused to open'));
    // Another tab is holding an older version open. Rare, and silent failure
    // here would look like an empty drug list.
    req.onblocked = () => reject(new Error('CLINIC_DB_BLOCKED'));
  });

  return dbPromise;
}

function run<T>(
  store: StoreName,
  mode: IDBTransactionMode,
  fn: (s: IDBObjectStore) => IDBRequest<T>
): Promise<T> {
  return openDb().then(
    (db) =>
      new Promise<T>((resolve, reject) => {
        const tx = db.transaction(store, mode);
        const req = fn(tx.objectStore(store));
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
        tx.onabort = () => reject(tx.error);
      })
  );
}

export function put<T>(store: StoreName, value: T, key?: IDBValidKey): Promise<unknown> {
  return run(store, 'readwrite', (s) => s.put(value, key));
}

export function get<T>(store: StoreName, key: IDBValidKey): Promise<T | undefined> {
  return run<T | undefined>(store, 'readonly', (s) => s.get(key) as IDBRequest<T | undefined>);
}

export function getAll<T>(store: StoreName): Promise<T[]> {
  return run<T[]>(store, 'readonly', (s) => s.getAll() as IDBRequest<T[]>);
}

export function del(store: StoreName, key: IDBValidKey): Promise<unknown> {
  return run(store, 'readwrite', (s) => s.delete(key));
}

export function clear(store: StoreName): Promise<unknown> {
  return run(store, 'readwrite', (s) => s.clear());
}

/** Bulk write in ONE transaction — the catalogue is thousands of rows. */
export async function putMany<T>(store: StoreName, values: T[]): Promise<void> {
  if (values.length === 0) return;
  const db = await openDb();
  await new Promise<void>((resolve, reject) => {
    const tx = db.transaction(store, 'readwrite');
    const s = tx.objectStore(store);
    for (const v of values) s.put(v);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
    tx.onabort = () => reject(tx.error);
  });
}

// ---------------------------------------------------------------- meta ----

export const META = {
  catalogVersion: 'catalog_version',
  catalogSyncedAt: 'catalog_synced_at',
  /** `${rx_prefix}:${yyyymmdd}` → last counter used. See rxNumber(). */
  rxCounter: (prefix: string, day: string) => `rx_counter:${prefix}:${day}`,
} as const;

export function getMeta<T>(key: string): Promise<T | undefined> {
  return get<T>(STORES.meta, key);
}

export function setMeta<T>(key: string, value: T): Promise<unknown> {
  return put(STORES.meta, value, key);
}

/**
 * Read-increment-write inside ONE transaction, returning the new value.
 *
 * Two separate getMeta/setMeta calls would race between tabs — the clinic
 * laptop with the queue open in one tab and a patient in another is the normal
 * setup, and two prescriptions numbered 047 is exactly the sort of collision
 * that only shows up when the internet comes back.
 */
export async function bumpCounter(key: string): Promise<number> {
  const db = await openDb();
  return new Promise<number>((resolve, reject) => {
    const tx = db.transaction(STORES.meta, 'readwrite');
    const s = tx.objectStore(STORES.meta);
    const read = s.get(key);
    read.onsuccess = () => {
      const next = (typeof read.result === 'number' ? read.result : 0) + 1;
      s.put(next, key);
      tx.oncomplete = () => resolve(next);
    };
    read.onerror = () => reject(read.error);
    tx.onabort = () => reject(tx.error);
  });
}

/**
 * Wipes every trace of the clinic from this device.
 *
 * Called on sign-out. A shared laptop at the reception desk is the normal case,
 * and leaving one doctor's patient list readable by the next person to sit down
 * is not acceptable — even though the outbox is dropped with it, which is why
 * signOut() refuses while anything is still queued.
 */
export async function wipeLocal(): Promise<void> {
  if (!hasLocalDb()) return;
  for (const name of Object.values(STORES)) await clear(name);
}
