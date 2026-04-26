'use client'

import { LoginScreen } from '@/components/auth/login-screen'
import { useAuth } from '@/hooks/use-auth'

export default function Home() {
  const { isLoading, isAuthenticated, employee, error } = useAuth()

  if (isLoading || error || !isAuthenticated) {
    return <LoginScreen />
  }

  return (
    <main className="min-h-screen bg-gray-50 p-6">
      <div className="max-w-sm mx-auto">
        <div className="bg-white rounded-2xl shadow-sm p-6">
          <h1 className="text-xl font-semibold text-gray-800 mb-1">
            สวัสดี, {employee?.nickname} 👋
          </h1>
          <p className="text-sm text-gray-500">
            {employee?.role} · Morya HR
          </p>
        </div>
      </div>
    </main>
  )
}