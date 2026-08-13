// قراءة قايمة أدوية ملزوقة من أي مكان.
//
// AUTHORED AS .js ON PURPOSE, same as arabic.js and phone.js: the harness
// imports this exact file and runs the real shapes through it. A parser that is
// only ever exercised by hand is a parser nobody is testing, and this one takes
// input from outside the system by definition.
//
// THE INPUT IS WHATEVER THE CLINIC ALREADY HAS. An Excel sheet copied to the
// clipboard arrives tab-separated. A .csv exported from an old system arrives
// comma-separated, sometimes with quoted fields containing commas. A list typed
// into WhatsApp arrives one name per line with no columns at all. All three are
// "the drug list", and refusing two of them means the feature goes unused.
//
// So: the separator is detected, a header row is recognised if present and
// skipped if not, and a single column is treated as trade names.

const CANON = {
  trade_name: ['trade_name', 'trade', 'brand', 'name', 'الاسم', 'الاسم التجاري', 'اسم الدواء', 'الدواء', 'الدوا'],
  trade_name_ar: ['trade_name_ar', 'arabic', 'الاسم بالعربي', 'الاسم العربي', 'عربي'],
  generic_ar: ['generic_ar', 'generic', 'المادة الفعالة', 'المادة', 'الفعالة'],
  generic_en: ['generic_en', 'active', 'ingredient', 'active ingredient'],
  form_ar: ['form_ar', 'form', 'الشكل', 'الشكل الصيدلي', 'العبوة'],
  strength: ['strength', 'dose', 'التركيز', 'الجرعة', 'التركيزات'],
};

/**
 * Which of our fields, if any, this header cell names.
 * @param {unknown} cell
 * @returns {string | null}
 */
function matchColumn(cell) {
  const v = String(cell ?? '').trim().toLowerCase().replace(/[_\s-]+/g, ' ');
  if (v === '') return null;
  for (const [field, names] of Object.entries(CANON)) {
    if (names.some((n) => n.toLowerCase().replace(/[_\s-]+/g, ' ') === v)) return field;
  }
  return null;
}

/**
 * Splits one line, honouring "quoted, fields" the way a spreadsheet export
 * writes them. Without this, a strength of "1,5 جم" — which is how a comma
 * decimal is written in much of the world — silently becomes two columns and
 * shifts every field after it.
 *
 * @param {string} line @param {string} sep
 */
function splitLine(line, sep) {
  const out = [];
  let cur = '';
  let quoted = false;

  for (let i = 0; i < line.length; i += 1) {
    const ch = line[i];
    if (quoted) {
      if (ch === '"') {
        if (line[i + 1] === '"') { cur += '"'; i += 1; }   // "" is a literal quote
        else quoted = false;
      } else cur += ch;
    } else if (ch === '"') {
      quoted = true;
    } else if (ch === sep) {
      out.push(cur); cur = '';
    } else {
      cur += ch;
    }
  }
  out.push(cur);
  return out.map((c) => c.trim());
}

/**
 * One parsed drug. Typed as an index signature rather than six named fields
 * because the parser fills it BY COLUMN NAME — `rec[field] = …` where `field`
 * came from the pasted header — and a closed shape cannot be written to that
 * way without a cast that would defeat the point of checking it.
 *
 * @typedef {Record<string, string>} ImportedDrug
 */

/**
 * @typedef {object} ParsedImport
 * @property {ImportedDrug[]} rows
 * @property {string[]} columns  which field each column was read as
 * @property {number} ignored    lines with nothing usable on them
 * @property {boolean} hadHeader
 */

/**
 * @param {string} text
 * @returns {ParsedImport}
 */
export function parseDrugList(text) {
  const lines = String(text ?? '')
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l !== '');

  if (lines.length === 0) {
    return { rows: [], columns: [], ignored: 0, hadHeader: false };
  }

  // Tab wins when present: a paste out of Excel is tab-separated, and its cells
  // routinely contain commas. Checking tabs first avoids shredding those.
  const first = lines[0];
  const sep = first.includes('\t') ? '\t' : first.includes(';') ? ';' : ',';

  const cells = lines.map((l) => splitLine(l, sep));

  // A header row is one where at least two cells NAME a field. One match is not
  // enough — a list whose first drug happens to be called "Name" would lose its
  // first row.
  const headerMatches = cells[0].map(matchColumn);
  const hadHeader = headerMatches.filter(Boolean).length >= 2;

  /** @type {(string|null)[]} */
  let columns;
  if (hadHeader) {
    columns = headerMatches;
  } else if (cells[0].length === 1) {
    // One column: it is a list of names. The commonest paste of all.
    columns = ['trade_name'];
  } else {
    // No header, several columns — assume the order the export screen uses and
    // say so on screen, because a wrong guess here is silent otherwise.
    columns = ['trade_name', 'trade_name_ar', 'generic_ar', 'form_ar', 'strength'];
  }

  const body = hadHeader ? cells.slice(1) : cells;
  const rows = [];
  let ignored = 0;

  for (const row of body) {
    /** @type {Record<string, string>} */
    const rec = {
      trade_name: '', trade_name_ar: '', generic_ar: '',
      generic_en: '', form_ar: '', strength: '',
    };
    columns.forEach((field, i) => {
      if (field && row[i] != null) rec[field] = row[i];
    });

    if (rec.trade_name === '') { ignored += 1; continue; }
    rows.push(rec);
  }

  return {
    rows,
    columns: columns.map((c) => c ?? '—'),
    ignored,
    hadHeader,
  };
}

/** Arabic labels for the detected columns, for the preview table. */
export const COLUMN_LABEL = {
  trade_name: 'الاسم التجاري',
  trade_name_ar: 'الاسم بالعربي',
  generic_ar: 'المادة الفعالة',
  generic_en: 'Generic',
  form_ar: 'الشكل',
  strength: 'التركيز',
  '—': 'اتجاهل',
};
