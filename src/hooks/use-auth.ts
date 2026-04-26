'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'
import { getLiffProfile } from '@/lib/line/liff'

type Employee = {
  id: string
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

export function useAuth(): AuthState {
  const [employee, setEmployee] = useState<Employee | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    async function authenticate() {
      try {
        const supabase = createClient()

        // เช็ค session ที่มีอยู่แล้วก่อน
        const { data: { session } } = await supabase.auth.getSession()

        if (session) {
          const meta = session.user.user_metadata
          setEmployee({
            id: meta.employee_id,
            code: null,
            nickname: meta.display_name,
            role: meta.role,
          })
          setIsLoading(false)
          return
        }

        // ถ้าไม่มี session → login ด้วย LIFF
        const profile = await getLiffProfile()

        if (!profile?.idToken) {
          setError('ไม่สามารถ login ด้วย LINE ได้')
          setIsLoading(false)
          return
        }

        // ส่ง idToken ไปยัง Edge Function
        const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!
        const res = await fetch(`${supabaseUrl}/functions/v1/line-auth`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ idToken: profile.idToken }),
        })

        if (!res.ok) {
          const err = await res.json()
          setError(err.error ?? 'Authentication failed')
          setIsLoading(false)
          return
        }

        const { session: newSession, employee: emp } = await res.json()

        // Set session ใน Supabase client
        await supabase.auth.setSession({
          access_token: newSession.access_token,
          refresh_token: newSession.refresh_token,
        })

        setEmployee(emp)

      } catch (err) {
        setError(err instanceof Error ? err.message : 'Authentication error')
      } finally {
        setIsLoading(false)
      }
    }

    authenticate()
  }, [])

  return {
    employee,
    isLoading,
    isAuthenticated: !!employee,
    error,
  }
}