// app/approve/page.tsx
// หน้าหลัก Supervisor/HR/Owner — อนุมัติ Leave + OT

'use client'

import { useState } from 'react'
import { useAuth } from '@/hooks/use-auth'
import { useLeave } from '@/hooks/use-leave'
import { useOt } from '@/hooks/use-ot'
import { LeaveApproveList } from '@/components/leave/leave-approve-list'
import { OtApproveList } from '@/components/ot/ot-approve-list'

const ALLOWED_ROLES = ['supervisor', 'hr_admin', 'owner', 'owner_delegate']

export default function ApprovePage() {
  const { employee, isLoading: authLoading } = useAuth()
  const { approveLeave, approving: approvingLeave } = useLeave(employee?.id ?? '')
  const { approveOt, approving: approvingOt }       = useOt(employee?.id ?? '')

  const [tab, setTab] = useState<'leave' | 'ot'>('leave')

  if (authLoading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <p className="text-sm text-gray-400">กำลังโหลด...</p>
      </div>
    )
  }

  if (!employee || !ALLOWED_ROLES.includes(employee.role)) {
    return (
      <div className="flex items-center justify-center min-h-screen px-6">
        <div className="text-center space-y-2">
          <p className="text-sm font-medium text-gray-700">ไม่มีสิทธิ์เข้าถึง</p>
          <p className="text-xs text-gray-400">สำหรับ Supervisor / HR / Owner เท่านั้น</p>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-gray-50">

      {/* Header */}
      <div className="bg-white border-b border-gray-100 px-4 py-3 sticky top-0 z-10">
        <h1 className="text-base font-semibold text-gray-900">อนุมัติ</h1>
        <p className="text-xs text-gray-400 mt-0.5">
          {employee.nickname ?? employee.code} · {employee.role}
        </p>
      </div>

      {/* Tabs */}
      <div className="bg-white border-b border-gray-100 px-4 flex gap-4">
        {(['leave', 'ot'] as const).map(t => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className={[
              'py-3 text-sm font-medium border-b-2 transition-colors',
              tab === t
                ? 'border-blue-500 text-blue-600'
                : 'border-transparent text-gray-400',
            ].join(' ')}
          >
            {t === 'leave' ? 'คำขอลา' : 'คำขอ OT'}
          </button>
        ))}
      </div>

      {/* Content */}
      <div className="px-4 py-4 max-w-md mx-auto">
        {tab === 'leave' ? (
          <LeaveApproveList
            approverId={employee.id}
            onApprove={approveLeave}
            isApproving={approvingLeave}
          />
        ) : (
          <OtApproveList
            approverId={employee.id}
            onApprove={approveOt}
            isApproving={approvingOt}
          />
        )}
      </div>

    </div>
  )
}