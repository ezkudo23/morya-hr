'use client'

import { createContext, useContext, useEffect, useState } from 'react'
import { initLiff, getLiffProfile } from '@/lib/line/liff'

type LiffProfile = {
  userId: string
  displayName: string
  pictureUrl?: string
  accessToken: string | null
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
        const message = err instanceof Error ? err.message : 'LIFF init failed'
        // กรอง LIFF warning ปกติออก ไม่ set error
        if (!message.includes('not related to the endpoint')) {
          setError(message)
        }
        // ให้ app render ต่อได้แม้ init fail
        setIsReady(true)
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