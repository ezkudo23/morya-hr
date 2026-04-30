
import type { Metadata } from 'next'
import { IBM_Plex_Sans_Thai } from 'next/font/google'
import './globals.css'
import { LiffProvider } from '@/components/providers/liff-provider'

const ibmPlexSansThai = IBM_Plex_Sans_Thai({
  subsets: ['thai', 'latin'],
  weight: ['300', '400', '500', '600', '700'],
  variable: '--font-ibm-plex-sans-thai',
})

export const metadata: Metadata = {
  title: 'Morya HR',
  description: 'ระบบ HR หมอยาสุรินทร์',
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="th">
      <body className={`${ibmPlexSansThai.variable} font-sans antialiased`}>
        <LiffProvider>
          {children}
        </LiffProvider>
      </body>
    </html>
  )
}