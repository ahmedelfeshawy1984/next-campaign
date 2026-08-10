import { S } from '@/lib/strings';

/**
 * Shown instead of the site when the Supabase keys are missing.
 *
 * The sibling projects both ship this screen, for a reason worth repeating: a
 * catalogue with no products in it looks like a broken database, and the person
 * seeing it goes looking in the wrong place. This says exactly which file to
 * edit.
 */
export default function SetupRequired() {
  return (
    <div className="setup">
      <h1>{S.setup.title}</h1>
      <p className="lead">{S.setup.body}</p>
      <ol>
        <li>{S.setup.step1}</li>
        <li>{S.setup.step2}</li>
        <li>{S.setup.step3}</li>
      </ol>
      <p style={{ marginBlockStart: 18, fontSize: '0.9rem', color: 'var(--ink-faint)' }}>
        الملف المطلوب: <code>web/.env.local</code>
      </p>
    </div>
  );
}
