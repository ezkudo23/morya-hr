// app/ot/page.tsx
// หน้าหลัก OT — Staff ขอ OT + ดูประวัติ

'use client'

import { useState } from 'react'
import { useAuth } from '@/hooks/use-auth'
import { useOt, OT_TYPE_LABELS } from '@/hooks/use-ot'
import { OtRequestForm } from '@/components/ot/ot-request-form'

const STATUS_LABEL: Record<string, string> = {
  pending:   'รออนุมัติ',
  approved:  'อนุมัติแล้ว',
  rejected:  'ไม่อนุมัติ',
  cancelled: 'ยกเลิก',
}

const STATUS_COLOR: Record<string, string> = {
  pending:   'bg-amber-50 text-amber-600',
  approved:  'bg-green-50 text-green-600',
  rejected:  'bg-red-50 text-red-600',
  cancelled: 'bg-gray-100 text-gray-400',
}

export default function OtPage() {
  const { employee, isLoading: authLoading } = useAuth()
  const {
    myOtRequests,
    loading,
    submitting,
    submitOt,
    fetchMyOt,
  } = useOt(employee?.id ?? '')

  const [tab, setTab] = useState<'request' | 'history'>('request')

  const toThaiDate = (dateStr: string) =>
    new Date(dateStr).toLocaleDateString('th-TH', {
      year: 'numeric', month: 'short', day: 'numeric',
    })

  if (authLoading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <p className="text-sm text-gray-400">กำลังโหลด...</p>
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
      <div className="bg-white border-b border-gray-100 px-4 py-3 sticky top-0 z-10">
        <h1 className="text-base font-semibold text-gray-900">ขอ OT</h1>
        <p className="text-xs text-gray-400 mt-0.5">
          {employee.nickname ?? employee.code}
        </p>
      </div>

      {/* Tabs */}
      <div className="bg-white border-b border-gray-100 px-4 flex gap-4">
        {(['request', 'history'] as const).map(t => (
          <button
            key={t}
            onClick={() => {
              setTab(t)
              if (t === 'history') fetchMyOt()
            }}
            className={[
              'py-3 text-sm font-medium border-b-2 transition-colors',
              tab === t
                ? 'border-blue-500 text-blue-600'
                : 'border-transparent text-gray-400',
            ].join(' ')}
          >
            {t === 'request' ? 'ขอ OT' : 'ประวัติ'}
          </button>
        ))}
      </div>

      {/* Content */}
      <div className="px-4 py-4 max-w-md mx-auto w-full overflow-hidden">

        {/* Tab: Request */}
        {tab === 'request' && (
          <OtRequestForm
            employeeId={employee.id}
            onSubmit={submitOt}
            isSubmitting={submitting}
          />
        )}

        {/* Tab: History */}
        {tab === 'history' && (
          <div className="space-y-3">
            {loading ? (
              <p className="text-sm text-gray-400 text-center py-8">กำลังโหลด...</p>
            ) : myOtRequests.length === 0 ? (
              <div className="text-center py-12 space-y-2">
                <p className="text-2xl">📋</p>
                <p className="text-sm text-gray-400">ยังไม่มีประวัติขอ OT</p>
              </div>
            ) : (
              myOtRequests.map(ot => (
                <div
                  key={ot.id}
                  className="bg-white border border-gray-200 rounded-xl px-4 py-3 space-y-2"
                >
                  <div className="flex items-center justify-between">
                    <span className="text-sm font-medium text-gray-900">
                      {toThaiDate(ot.work_date)}
                    </span>
                    <span className={[
                      'text-xs font-medium px-2 py-0.5 rounded-full',
                      STATUS_COLOR[ot.status],
                    ].join(' ')}>
                      {STATUS_LABEL[ot.status]}
                    </span>
                  </div>
                  <div className="flex items-center justify-between">
                    <span className="text-xs text-gray-500">
                      {ot.start_time.slice(0,5)}–{ot.end_time.slice(0,5)} · {ot.ot_hours} ชม.
                    </span>
                    <span className="text-xs text-gray-400">
                      {OT_TYPE_LABELS[ot.ot_type]}
                    </span>
                  </div>
                  {ot.reason && (
                    <p className="text-xs text-gray-400">{ot.reason}</p>
                  )}
                  {ot.approver_note && ot.status === 'rejected' && (
                    <p className="text-xs text-red-400">
                      เหตุผล: {ot.approver_note}
                    </p>
                  )}
                </div>
              ))
            )}
          </div>
        )}

      </div>
    </div>
  )
}