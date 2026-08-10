'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { basketCount } from '@/lib/basket';

/**
 * The quote basket in the header.
 *
 * Renders NOTHING until there is something in it. An always-visible empty
 * basket on a catalogue whose main call to action is "configure this" is just
 * furniture — and it would be the only header item that means nothing to a
 * first-time visitor.
 */
export default function BasketLink() {
  const [count, setCount] = useState(0);

  useEffect(() => {
    const sync = () => setCount(basketCount());
    sync();
    // 'nc:basket' is dispatched by lib/basket on every write, so adding from a
    // product page updates the header without a reload. 'storage' covers a
    // second tab.
    window.addEventListener('nc:basket', sync);
    window.addEventListener('storage', sync);
    return () => {
      window.removeEventListener('nc:basket', sync);
      window.removeEventListener('storage', sync);
    };
  }, []);

  if (!count) return null;

  return (
    <Link href="/quote" className="basket-link">
      عرض السعر
      <span className="basket-link__count num">{count}</span>
    </Link>
  );
}
