'use client'

import { createContext, useContext, useEffect, useState } from 'react'
import { initLiff, getLiffProfile } from '@/lib/line/liff'

type LiffProfile = {
  userId: string
  displayName: string
  pictureUrl?: string
  idToken: string | null
} | null

type LiffContextType = {
  profile: LiffProfile
  isLoading: boolean
  isReady: boolean
  error: string | null
}

const LiffContext = createContext<LiffContextType>({
  profile: null,
  isLoading: true,
  isReady: false,
  error: null,
})

export function LiffProvider({ children }: { children: React.ReactNode }) {
  const [profile, setProfile] = useState<LiffProfile>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [isReady, setIsReady] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    async function init() {
      try {
        await initLiff()
        const userProfile = await getLiffProfile()
        setProfile(userProfile)
        setIsReady(true)
      } catch (err) {
        setError(err instanceof Error ? err.message : 'LIFF init failed')
      } finally {
        setIsLoading(false)
      }
    }

    init()
  }, [])

  return (
    <LiffContext.Provider value={{ profile, isLoading, isReady, error }}>
      {children}
    </LiffContext.Provider>
  )
}

export function useLiff() {
  return useContext(LiffContext)
}