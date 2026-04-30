'use client'

import { useLiff } from '@/components/providers/liff-provider'
import { useAuth } from '@/hooks/use-auth'

export function LoginScreen() {
  const { isLoading: liffLoading, error: liffError } = useLiff()
  const { isLoading: authLoading, error: authError } = useAuth()

  const isLoading = liffLoading || authLoading
  const error = liffError ?? authError

  if (isLoading) {
    return (
      <div className="min-h-screen flex flex-col items-center justify-center bg-white">
        <div className="flex flex-col items-center gap-4">
          <div className="w-12 h-12 rounded-full border-4 border-green-500 border-t-transparent animate-spin" />
          <p className="text-gray-500 text-sm">กำลังเข้าสู่ระบบ...</p>
        </div>
      </div>
    )
  }

  if (error) {
    return (
      <div className="min-h-screen flex flex-col items-center justify-center bg-white px-6">
        <div className="flex flex-col items-center gap-4 text-center">
          <div className="w-16 h-16 rounded-full bg-red-100 flex items-center justify-center">
            <span className="text-2xl">⚠️</span>
          </div>
          <h2 className="text-lg font-semibold text-gray-800">ไม่สามารถเข้าสู่ระบบได้</h2>
          <p className="text-sm text-gray-500">{error}</p>
          <p className="text-xs text-gray-400">กรุณาติดต่อ IT Support (บอส)</p>
        </div>
      </div>
    )
  }

  return null
}