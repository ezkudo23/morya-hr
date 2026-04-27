// components/leave/leave-balance-card.tsx
// หน้าที่: แสดง quota คงเหลือแต่ละประเภทลา

'use client'

import { LeaveBalance, LeaveType, LEAVE_TYPE_LABELS, LEAVE_TYPE_QUOTA } from '@/hooks/use-leave'

interface LeaveBalanceCardProps {
  balances:     LeaveBalance[]
  pending:      Record<LeaveType, number>
  isProbation:  boolean
  isLoading:    boolean
  onSelectType: (type: LeaveType) => void
}

export function LeaveBalanceCard({
  balances,
  pending,
  isProbation,
  isLoading,
  onSelectType,
}: LeaveBalanceCardProps) {

  if (isLoading) {
    return (
      <div className="space-y-2">
        {Array.from({ length: 3 }).map((_, i) => (
          <div key={i} className="h-16 rounded-xl bg-gray-100 animate-pulse" />
        ))}
      </div>
    )
  }

  return (
    <div className="space-y-3">

      {/* Probation Banner */}
      {isProbation && (
        <div className="rounded-xl bg-amber-50 border border-amber-200 px-4 py-3">
          <p className="text-sm font-medium text-amber-800">⚠️ อยู่ในช่วงทดลองงาน</p>
          <p className="text-xs text-amber-600 mt-0.5">
            ลาพักร้อนและลากิจยังไม่พร้อมใช้งาน
          </p>
        </div>
      )}

      {/* Balance List */}
      {balances.map((b) => {
        const pendingDays = pending[b.leave_type] ?? 0
        const effectiveRemaining = b.remaining_days - pendingDays
        const pct = b.entitled_days > 0
          ? Math.max(0, (effectiveRemaining / b.entitled_days) * 100)
          : 0

        return (
          <button
            key={b.leave_type}
            onClick={() => b.available && onSelectType(b.leave_type)}
            disabled={!b.available}
            className={[
              'w-full text-left rounded-xl border px-4 py-3 transition-all',
              b.available
                ? 'bg-white border-gray-200 active:scale-[0.98] cursor-pointer'
                : 'bg-gray-50 border-gray-100 opacity-60 cursor-not-allowed',
            ].join(' ')}
          >
            <div className="flex items-center justify-between mb-2">
              <div>
                <span className="text-sm font-medium text-gray-900">
                  {LEAVE_TYPE_LABELS[b.leave_type]}
                </span>
                <span className="ml-2 text-xs text-gray-400">
                  {LEAVE_TYPE_QUOTA[b.leave_type]}
                </span>
              </div>

              <div className="text-right">
                {b.leave_type === 'military' ? (
                  <span className="text-xs text-gray-500">ตามหมายเรียก</span>
                ) : (
                  <span className={[
                    'text-sm font-semibold',
                    effectiveRemaining <= 0   ? 'text-red-500'
                    : effectiveRemaining <= 1 ? 'text-amber-500'
                    : 'text-green-600',
                  ].join(' ')}>
                    {effectiveRemaining}
                    <span className="text-xs font-normal text-gray-400 ml-0.5">วัน</span>
                  </span>
                )}
              </div>
            </div>

            {/* Progress bar */}
            {b.leave_type !== 'military' && b.entitled_days > 0 && (
              <div className="h-1.5 w-full rounded-full bg-gray-100 overflow-hidden">
                <div
                  className={[
                    'h-full rounded-full transition-all',
                    pct > 50  ? 'bg-green-400'
                    : pct > 20 ? 'bg-amber-400'
                    : 'bg-red-400',
                  ].join(' ')}
                  style={{ width: `${pct}%` }}
                />
              </div>
            )}

            {/* Pending badge */}
            {pendingDays > 0 && (
              <p className="text-xs text-amber-600 mt-1.5">
                ⏳ รออนุมัติ {pendingDays} วัน
              </p>
            )}

            {/* Unavailable reason */}
            {!b.available && b.unavailable_reason && (
              <p className="text-xs text-gray-400 mt-1">
                {b.unavailable_reason === 'PROBATION_NO_ANNUAL'   && 'ได้รับสิทธิ์หลังครบ 1 ปี'}
                {b.unavailable_reason === 'PROBATION_NO_PERSONAL' && 'ไม่พร้อมใช้ระหว่างทดลองงาน'}
                {b.unavailable_reason === 'QUOTA_EXHAUSTED'       && 'โควต้าหมดแล้ว'}
              </p>
            )}

            {/* Tags */}
            <div className="flex gap-1.5 mt-2">
              {b.supports_half_day && (
                <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-blue-50 text-blue-500">
                  ครึ่งวันได้
                </span>
              )}
              {b.supports_backdate && (
                <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-purple-50 text-purple-500">
                  ลาย้อนหลังได้
                </span>
              )}
            </div>
          </button>
        )
      })}
    </div>
  )
}