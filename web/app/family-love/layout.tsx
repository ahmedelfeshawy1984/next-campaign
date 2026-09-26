import type { Metadata, Viewport } from 'next';
import ServiceWorker from '@/components/family-love/ServiceWorker';
import './family-love.css';

export const metadata: Metadata = {
  title: 'عائلتي — Family Love',
  description: 'متابعة يومية بين الأهل والطفل: مهام ومحطات، تنبيهات، وموقع لحظي.',
  openGraph: { title: 'عائلتي', description: 'متابعة يومية بين الأهل والطفل.' },
  // مش هيتفهرس أبدًا — نفس قرار العيادة، لنفس السبب: منتج منفصل جوه نفس
  // المستودع، مش جزء من الشوب.
  robots: { index: false, follow: false, nocache: true },
  manifest: '/family-love.webmanifest',
  // سفاري مابيرندرش SVG لأيقونة الشاشة الرئيسية — لازم PNG حقيقي هنا.
  icons: { apple: '/family-love-apple-touch-icon.png' },
  appleWebApp: { capable: true, title: 'عائلتي', statusBarStyle: 'default' },
};

export const viewport: Viewport = {
  initialScale: 1,
  maximumScale: 1,
  width: 'device-width',
  themeColor: '#0f766e',
};

export default function FamilyLoveLayout({ children }: { children: React.ReactNode }) {
  return (
    <main id="main" className="fl">
      <ServiceWorker />
      {children}
    </main>
  );
}
