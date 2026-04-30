'use client'

import { LoginScreen } from '@/components/auth/login-screen'
import { CheckInButton } from '@/components/attendance/check-in-button'
import { useAuth } from '@/hooks/use-auth'
import { useLiff } from '@/components/providers/liff-provider'

export default function Home() {
  const { profile, isLoading: liffLoading, isReady } = useLiff()
  const { isLoading: authLoading, isAuthenticated, employee, error } = useAuth(
    isReady ? (profile?.accessToken ?? null) : undefined
  )

  const isLoading = liffLoading || authLoading

  if (isLoading || error || !isAuthenticated) {
    return <LoginScreen isLoading={isLoading} error={error} />
  }

  return (
    <main className="min-h-screen bg-gray-50">
      <div className="max-w-sm mx-auto pt-8">
        <div className="bg-white rounded-2xl shadow-sm mb-4 p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-xs text-gray-400">Morya HR</p>
              <p className="text-sm font-medium text-gray-700">{employee?.role}</p>
            </div>
            <div className="w-10 h-10 rounded-full bg-green-100 flex items-center justify-center">
              <span className="text-green-600 font-bold">
                {employee?.nickname?.charAt(0)}
              </span>
            </div>
          </div>
        </div>
        <div className="bg-white rounded-2xl shadow-sm">
          <CheckInButton
            employeeId={employee?.id ?? ''}
            nickname={employee?.nickname ?? ''}
          />
        </div>
      </div>
    </main>
  )
}