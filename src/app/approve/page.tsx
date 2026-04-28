'use client'

import { useAuth } from '@/hooks/use-auth'
import { useLeave } from '@/hooks/use-leave'
import { LeaveApproveList } from '@/components/leave/leave-approve-list'

const ALLOWED_ROLES = ['supervisor', 'hr_admin', 'owner', 'owner_delegate']

export default function ApprovePage() {
  const { employee, isLoading: authLoading } = useAuth()
  const { approveLeave, approving } = useLeave(employee?.id ?? null)

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

  if (!ALLOWED_ROLES.includes(employee.role)) {
    return (
      <div className="flex items-center justify-center min-h-screen px-6">
        <div className="text-center space-y-2">
          <p className="text-sm font-medium text-gray-700">ไม่มีสิทธิ์เข้าถึง</p>
          <p className="text-xs text-gray-400">
            หน้านี้สำหรับ Supervisor / HR Admin / Owner เท่านั้น
          </p>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-gray-50">

      <div className="bg-white border-b border-gray-100 px-4 py-3 sticky top-0 z-10">
        <h1 className="text-base font-medium text-gray-900">อนุมัติคำขอลา</h1>
        <p className="text-xs text-gray-400 mt-0.5">
          {employee.nickname ?? employee.code} -{' '}
          {employee.role === 'supervisor'     && 'Supervisor'}
          {employee.role === 'hr_admin'       && 'HR Admin'}
          {employee.role === 'owner'          && 'Owner'}
          {employee.role === 'owner_delegate' && 'Owner Delegate'}
        </p>
      </div>

      <div className="px-4 py-4 max-w-md mx-auto">
        <LeaveApproveList
          approverId={employee.profile_id}
          onApprove={approveLeave}
          isApproving={approving}
        />
      </div>

    </div>
  )
}