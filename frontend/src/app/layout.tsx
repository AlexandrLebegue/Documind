import type { Metadata } from 'next';
import './globals.css';
import LayoutShell from '@/components/LayoutShell';

export const metadata: Metadata = {
  title: 'DocuMind — Gestion documentaire intelligente',
  description: 'Application locale de gestion et analyse de documents avec IA',
  icons: {
    icon: '/icon.svg',
  },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="fr">
      <body className="bg-beige-100 text-[#1a1a1a]">
        <LayoutShell>{children}</LayoutShell>
      </body>
    </html>
  );
}
