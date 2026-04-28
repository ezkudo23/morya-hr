// app/leave/history/page.tsx
// หน้าประวัติการลาของพนักงาน

'use client'

import { useAuth } from '@/hooks/use-auth'
import { LeaveHistoryList } from '@/components/leave/leave-history-list'
import { useRouter } from 'next/navigation'

export default function LeaveHistoryPage() {
  const { employee, isLoading: authLoading } = useAuth()
  const router = useRouter()

  if (authLoading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <div className="text-sm text-gray-400">กำลังโหลด...</div>
      </div>
    )
  }

  if (!employee) {
    return (
      <div className="flex items-center justify-center min-h-screen px-6">
        <div className="text-center space-y-2">
          <p className="text-sm font-medium text-gray-700">กรุณาเข้าสู่ระบบ</p>
          <p className="text-xs text-gray-400">เปิดผ่าน LINE เท่านั้น</p>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-gray-50">

      {/* Header */}
      <div className="bg-white border-b border-gray-100 px-4 py-3 flex items-center gap-3 sticky top-0 z-10">
        <button
          onClick={() => router.back()}
          className="w-8 h-8 rounded-full bg-gray-100 flex items-center justify-center text-gray-500 flex-shrink-0"
          aria-label="ย้อนกลับ"
        >
          &lt;
        </button>
        <div>
          <h1 className="text-base font-medium text-gray-900">ประวัติการลา</h1>
          <p className="text-xs text-gray-400 mt-0.5">
            {employee.nickname ?? employee.code}
          </p>
        </div>
      </div>

      {/* Content */}
      <div className="px-4 py-4 max-w-md mx-auto">
        <LeaveHistoryList employeeId={employee.id} />
      </div>

    </div>
  )
}
