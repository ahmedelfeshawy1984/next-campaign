'use client';

import { useEffect, useRef, useState } from 'react';
import { loadCatalog, searchDrugs, type DrugHit } from '@/lib/clinic/drugs';
import type { Drug } from '@/lib/clinic/types';

// حقل الدواء — أول حرف يطلّع النتيجة.
//
// Nothing here is async on the keystroke path. searchDrugs() is a synchronous
// pass over an array already in memory, so there is no debounce, no spinner,
// no request, and — the point of the whole exercise — no difference in
// behaviour when the clinic's internet is down.
//
// A debounce would be the reflex thing to add and would make it worse: the
// delay it exists to hide does not exist here.

interface Props {
  value: string;
  onPick: (drug: Drug | null, typed: string) => void;
  placeholder?: string;
  autoFocus?: boolean;
}

export default function DrugPicker({ value, onPick, placeholder, autoFocus }: Props) {
  const [term, setTerm] = useState(value);
  const [hits, setHits] = useState<DrugHit[]>([]);
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(0);
  const [ready, setReady] = useState(false);
  const boxRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    loadCatalog().then((s) => setReady(s.drugs > 0));
  }, []);

  useEffect(() => setTerm(value), [value]);

  useEffect(() => {
    const onDocClick = (e: MouseEvent) => {
      if (boxRef.current && !boxRef.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener('mousedown', onDocClick);
    return () => document.removeEventListener('mousedown', onDocClick);
  }, []);

  function refresh(next: string) {
    setTerm(next);
    setHits(searchDrugs(next));
    setActive(0);
    setOpen(true);
    // Report the raw text on every keystroke. A drug that is not in the
    // catalogue still has to be prescribable — the line stores drug_name as a
    // snapshot, so free text prints and files perfectly well with a null
    // drug_id.
    onPick(null, next);
  }

  function choose(hit: Drug) {
    setTerm(hit.trade_name);
    setOpen(false);
    onPick(hit, hit.trade_name);
  }

  return (
    <div className="drugpick" ref={boxRef}>
      <input
        type="text"
        className="input"
        value={term}
        placeholder={placeholder ?? 'اسم الدوا…'}
        autoFocus={autoFocus}
        autoComplete="off"
        onChange={(e) => refresh(e.target.value)}
        onFocus={() => {
          setHits(searchDrugs(term));
          setOpen(true);
        }}
        onKeyDown={(e) => {
          if (!open || hits.length === 0) return;
          if (e.key === 'ArrowDown') {
            e.preventDefault();
            setActive((i) => Math.min(i + 1, hits.length - 1));
          } else if (e.key === 'ArrowUp') {
            e.preventDefault();
            setActive((i) => Math.max(i - 1, 0));
          } else if (e.key === 'Enter') {
            e.preventDefault();
            choose(hits[active]);
          } else if (e.key === 'Escape') {
            setOpen(false);
          }
        }}
        role="combobox"
        aria-expanded={open}
        aria-autocomplete="list"
      />

      {open && hits.length > 0 ? (
        <ul className="drugpick__list" role="listbox">
          {hits.map((h, i) => (
            <li key={h.id} role="option" aria-selected={i === active}>
              <button
                type="button"
                className={`drugpick__item${i === active ? ' is-active' : ''}`}
                onMouseEnter={() => setActive(i)}
                onClick={() => choose(h)}
              >
                <strong>{h.trade_name}</strong>
                {/* Shown, not just searched. A doctor who typed "كونكور" needs
                    to see that spelling in the row to be sure it is the drug
                    they meant, rather than reading Latin back at them. */}
                {h.trade_name_ar ? (
                  <span className="drugpick__ar"> {h.trade_name_ar}</span>
                ) : null}
                {h.strength ? <span className="num" dir="ltr"> {h.strength}</span> : null}
                {h.form_ar ? <span className="drugpick__form"> — {h.form_ar}</span> : null}
                {h.generic_ar ? <em className="drugpick__generic">{h.generic_ar}</em> : null}
              </button>
            </li>
          ))}
        </ul>
      ) : null}

      {open && term.trim() !== '' && hits.length === 0 ? (
        <p className="drugpick__none">
          مش في الكتالوج — هيتكتب زي ما هو في الروشتة.
        </p>
      ) : null}

      {!ready ? (
        <p className="drugpick__none">
          كتالوج الأدوية لسه بينزل على الجهاز — اكتب الاسم عادي لحد ما يخلص.
        </p>
      ) : null}
    </div>
  );
}
