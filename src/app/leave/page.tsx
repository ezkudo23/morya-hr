// app/leave/page.tsx
// หน้าหลัก Leave — LIFF Staff view
// รวม LeaveBalanceCard + LeaveRequestForm

'use client'

import { useState } from 'react'
import { useAuth } from '@/hooks/use-auth'
import { useLeave, LeaveType } from '@/hooks/use-leave'
import { LeaveBalanceCard } from '@/components/leave/leave-balance-card'
import { LeaveRequestForm } from '@/components/leave/leave-request-form'

type View = 'balance' | 'form'

export default function LeavePage() {
  const { employee, isLoading: authLoading } = useAuth()
  const [view, setView]               = useState<View>('balance')
  const [selectedType, setSelectedType] = useState<LeaveType | null>(null)

  const {
    balance,
    loadingBalance,
    submitting,
    submitLeave,
  } = useLeave(employee?.id ?? null)
    
  // ─── Loading ──────────────────────────────────
  if (authLoading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <div className="text-sm text-gray-400">กำลังโหลด...</div>
      </div>
    )
  }

  // ─── No session ───────────────────────────────
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

  // ─── PC Staff — ไม่มีสิทธิ์ลา ─────────────────
  if (employee.role === 'pc_staff') {
    return (
      <div className="flex items-center justify-center min-h-screen px-6">
        <div className="text-center space-y-2">
          <p className="text-sm font-medium text-gray-700">ไม่มีสิทธิ์ขอลา</p>
          <p className="text-xs text-gray-400">PC Staff ไม่อยู่ในระบบลา</p>
        </div>
      </div>
    )
  }

  // ─── Select leave type → go to form ──────────
  const handleSelectType = (type: LeaveType) => {
    setSelectedType(type)
    setView('form')
  }

  const handleBackToBalance = () => {
    setSelectedType(null)
    setView('balance')
  }

  // ─── Offline banner ───────────────────────────
  const OfflineBanner = () => {
    if (typeof navigator !== 'undefined' && !navigator.onLine) {
      return (
        <div className="mx-4 mt-3 rounded-xl bg-amber-50 border border-amber-200 px-4 py-3 flex gap-3 items-start">
          <div className="w-5 h-5 rounded-full bg-amber-200 flex items-center justify-center flex-shrink-0 mt-0.5">
            <span className="text-amber-800 text-xs font-bold">!</span>
          </div>
          <div>
            <p className="text-sm font-medium text-amber-800">ไม่มีสัญญาณอินเตอร์เน็ต</p>
            <p className="text-xs text-amber-600 mt-0.5">
              ไม่สามารถขอลาได้ตอนนี้ — กลับมาใหม่เมื่อมีสัญญาณ
            </p>
          </div>
        </div>
      )
    }
    return null
  }

  // ─── Render ───────────────────────────────────
  return (
    <div className="min-h-screen bg-gray-50">

      {/* Header */}
      <div className="bg-white border-b border-gray-100 px-4 py-3 flex items-center gap-3 sticky top-0 z-10">
        {view === 'form' && (
          <button
            onClick={handleBackToBalance}
            className="w-8 h-8 rounded-full bg-gray-100 flex items-center justify-center text-gray-500 flex-shrink-0"
            aria-label="ย้อนกลับ"
          >
            &#8592;
          </button>
        )}
        <div>
          <h1 className="text-base font-medium text-gray-900">
            {view === 'balance' ? 'ขอลา' : 'กรอกรายละเอียด'}
          </h1>
          {view === 'balance' && balance && (
            <p className="text-xs text-gray-400 mt-0.5">
              {employee.nickname ?? employee.code} · ปี {balance.year + 543}
              {balance.is_probation && (
                <span className="ml-2 text-amber-500">ทดลองงาน</span>
              )}
            </p>
          )}
        </div>
      </div>

      {/* Offline banner */}
      <OfflineBanner />

      {/* Content */}
      <div className="px-4 py-4 max-w-md mx-auto">

        {view === 'balance' && (
          <LeaveBalanceCard
            balances={balance?.balances ?? []}
            pending={balance?.pending ?? {} as Record<LeaveType, number>}
            isProbation={balance?.is_probation ?? false}
            isLoading={loadingBalance}
            onSelectType={handleSelectType}
          />
        )}

        {view === 'form' && selectedType && (
          <LeaveRequestForm
            employeeId={employee.id}
            selectedType={selectedType}
            balance={balance?.balances.find(b => b.leave_type === selectedType)}
            onSubmit={submitLeave}
            onCancel={handleBackToBalance}
            isSubmitting={submitting}
          />
        )}

      </div>
    </div>
  )
}