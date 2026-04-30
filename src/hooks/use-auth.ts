'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'
import { useLiff } from '@/components/providers/liff-provider'

type Employee = {
  id: string
  profile_id: string
  code: string | null
  nickname: string | null
  role: string
}

type AuthState = {
  employee: Employee | null
  isLoading: boolean
  isAuthenticated: boolean
  error: string | null
}

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!

export function useAuth(): AuthState {
  const { profile, isReady } = useLiff()
  const [employee, setEmployee] = useState<Employee | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    // รอ LIFF ready ก่อน
    if (!isReady) return

    async function authenticate() {
      try {
        const supabase = createClient()
        const { data: { session } } = await supabase.auth.getSession()

        if (session) {
          const meta = session.user.user_metadata
          setEmployee({
            id:         meta.employee_id,
            profile_id: session.user.id,
            code:       null,
            nickname:   meta.display_name,
            role:       meta.role,
          })
          setIsLoading(false)
          return
        }

        // ใช้ profile จาก liff-provider ไม่เรียก LIFF ซ้ำ
        if (!profile?.accessToken) {
          setError('ไม่สามารถ login ด้วย LINE ได้')
          setIsLoading(false)
          return
        }

        const res = await fetch(`${SUPABASE_URL}/functions/v1/line-auth`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ accessToken: profile.accessToken }),
        })

        if (!res.ok) {
          const err = await res.json()
          setError(err.error ?? 'Authentication failed')
          setIsLoading(false)
          return
        }

        const { session: newSession, employee: emp } = await res.json()

        const supabaseClient = createClient()
        await supabaseClient.auth.setSession({
          access_token:  newSession.access_token,
          refresh_token: newSession.refresh_token,
        })

        setEmployee({
          id:         emp.id,
          profile_id: newSession.user?.id ?? '',
          code:       emp.code,
          nickname:   emp.nickname,
          role:       emp.role,
        })

      } catch (err) {
        setError(err instanceof Error ? err.message : 'Authentication error')
      } finally {
        setIsLoading(false)
      }
    }

    authenticate()
  }, [isReady, profile])

  return {
    employee,
    isLoading,
    isAuthenticated: !!employee,
    error,
  }
}