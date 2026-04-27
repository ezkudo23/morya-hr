// components/leave/leave-request-form.tsx
// หน้าที่: form ขอลา — validate + submit

'use client'

import { useState } from 'react'
import {
  LeaveType,
  LEAVE_TYPE_LABELS,
  LeaveBalance,
  SubmitLeavePayload,
  SubmitLeaveResult,
} from '@/hooks/use-leave'

interface LeaveRequestFormProps {
  employeeId:    string
  selectedType:  LeaveType
  balance:       LeaveBalance | undefined
  onSubmit:      (payload: SubmitLeavePayload) => Promise<SubmitLeaveResult>
  onCancel:      () => void
  isSubmitting:  boolean
}

export function LeaveRequestForm({
  employeeId,
  selectedType,
  balance,
  onSubmit,
  onCancel,
  isSubmitting,
}: LeaveRequestFormProps) {

  const today = new Date().toISOString().split('T')[0]

  const [startDate,       setStartDate]       = useState(today)
  const [endDate,         setEndDate]         = useState(today)
  const [isHalfDay,       setIsHalfDay]       = useState(false)
  const [halfDayPeriod,   setHalfDayPeriod]   = useState<'morning' | 'afternoon'>('morning')
  const [isBackdate,      setIsBackdate]      = useState(false)
  const [reason,          setReason]          = useState('')
  const [attachmentUrl,   setAttachmentUrl]   = useState('')
  const [result,          setResult]          = useState<SubmitLeaveResult | null>(null)

  // คำนวณจำนวนวัน
  const calcDays = () => {
    if (isHalfDay) return 0.5
    const diff = Math.floor(
      (new Date(endDate).getTime() - new Date(startDate).getTime())
      / (1000 * 60 * 60 * 24)
    ) + 1
    return Math.max(0, diff)
  }

  const days = calcDays()

  // Approval routing label
  const approvalLabel = () => {
    if (days <= 3) return 'Supervisor'
    if (days <= 7) return 'Supervisor → HR Admin'
    return 'Supervisor → HR Admin → Owner'
  }

  const handleSubmit = async () => {
    const res = await onSubmit({
      employee_id:     employeeId,
      leave_type:      selectedType,
      start_date:      startDate,
      end_date:        isHalfDay ? startDate : endDate,
      is_half_day:     isHalfDay,
      half_day_period: isHalfDay ? halfDayPeriod : undefined,
      reason:          reason || undefined,
      attachment_url:  attachmentUrl || undefined,
      is_backdate:     isBackdate,
    })
    setResult(res)
  }

  // ─── Success State ────────────────────────────
  if (result?.success) {
    return (
      <div className="flex flex-col items-center justify-center py-10 text-center space-y-3">
        <div className="text-5xl">✅</div>
        <p className="text-lg font-semibold text-gray-900">ส่งคำขอลาแล้ว</p>
        <p className="text-sm text-gray-500">
          {LEAVE_TYPE_LABELS[selectedType]} · {result.days} วัน
        </p>
        <p className="text-xs text-gray-400">
          รออนุมัติจาก {approvalLabel()}
        </p>
        {!result.advance_notice_met && (
          <div className="rounded-lg bg-amber-50 border border-amber-200 px-4 py-2 text-xs text-amber-700">
            ⚠️ แจ้งล่วงหน้าไม่ครบตามกำหนด — อาจกระทบเบี้ยขยัน
          </div>
        )}
        <button
          onClick={onCancel}
          className="mt-4 text-sm text-blue-600 underline"
        >
          กลับหน้าหลัก
        </button>
      </div>
    )
  }

  // ─── Error State ──────────────────────────────
  const ERROR_MESSAGES: Record<string, string> = {
    INSUFFICIENT_BALANCE:       `โควต้าไม่พอ — เหลือ ${result?.remaining ?? 0} วัน`,
    BACKDATE_WINDOW_EXCEEDED:   'ลาย้อนหลังได้ไม่เกิน 3 วัน',
    BACKDATE_SICK_ONLY:         'ลาย้อนหลังได้เฉพาะลาป่วยเท่านั้น',
    ATTACHMENT_REQUIRED:        'ลาป่วย 3 วันขึ้นไปต้องแนบใบรับรองแพทย์',
    HALF_DAY_NOT_SUPPORTED:     'ประเภทลานี้ไม่รองรับการลาครึ่งวัน',
    PROBATION_NO_PERSONAL_LEAVE:'ช่วงทดลองงาน ลากิจถือเป็น LWP — ติดต่อ HR',
    PROBATION_NO_ANNUAL_LEAVE:  'ลาพักร้อนได้หลังครบ 1 ปี',
    PAST_DATE_NOT_ALLOWED:      'ไม่สามารถเลือกวันในอดีตได้',
    INVALID_DATE_RANGE:         'วันที่ไม่ถูกต้อง',
    NO_LEAVE_BALANCE:           'ไม่พบข้อมูล balance — ติดต่อ HR',
  }

  return (
    <div className="space-y-5">

      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-base font-semibold text-gray-900">
            {LEAVE_TYPE_LABELS[selectedType]}
          </h2>
          {balance && balance.leave_type !== 'military' && (
            <p className="text-xs text-gray-400 mt-0.5">
              คงเหลือ {balance.remaining_days} วัน
            </p>
          )}
        </div>
        <button
          onClick={onCancel}
          className="text-sm text-gray-400 hover:text-gray-600"
        >
          ยกเลิก
        </button>
      </div>

      {/* Error Banner */}
      {result && !result.success && (
        <div className="rounded-xl bg-red-50 border border-red-200 px-4 py-3">
          <p className="text-sm font-medium text-red-700">
            {ERROR_MESSAGES[result.error ?? ''] ?? result.error}
          </p>
          {result.hint && (
            <p className="text-xs text-red-500 mt-1">{result.hint}</p>
          )}
        </div>
      )}

      {/* Backdate toggle (ลาป่วยเท่านั้น) */}
      {selectedType === 'sick' && (
        <div className="flex items-center justify-between rounded-xl bg-purple-50 px-4 py-3">
          <div>
            <p className="text-sm font-medium text-purple-800">ลาย้อนหลัง</p>
            <p className="text-xs text-purple-500">window ≤ 3 วัน</p>
          </div>
          <button
            onClick={() => setIsBackdate(!isBackdate)}
            className={[
              'relative w-11 h-6 rounded-full transition-colors',
              isBackdate ? 'bg-purple-500' : 'bg-gray-200',
            ].join(' ')}
          >
            <span className={[
              'absolute top-0.5 left-0.5 w-5 h-5 rounded-full bg-white shadow transition-transform',
              isBackdate ? 'translate-x-5' : 'translate-x-0',
            ].join(' ')} />
          </button>
        </div>
      )}

      {/* วันที่ */}
      <div className="space-y-3">
        <label className="text-sm font-medium text-gray-700">วันที่ลา</label>

        {/* Half-day toggle */}
        {balance?.supports_half_day && (
          <div className="flex gap-2">
            {(['full', 'half'] as const).map((v) => (
              <button
                key={v}
                onClick={() => setIsHalfDay(v === 'half')}
                className={[
                  'flex-1 py-2 rounded-lg text-sm font-medium border transition-all',
                  (v === 'half') === isHalfDay
                    ? 'bg-blue-500 text-white border-blue-500'
                    : 'bg-white text-gray-600 border-gray-200',
                ].join(' ')}
              >
                {v === 'full' ? 'เต็มวัน' : 'ครึ่งวัน'}
              </button>
            ))}
          </div>
        )}

        {/* Half-day period */}
        {isHalfDay && (
          <div className="flex gap-2">
            {(['morning', 'afternoon'] as const).map((v) => (
              <button
                key={v}
                onClick={() => setHalfDayPeriod(v)}
                className={[
                  'flex-1 py-2 rounded-lg text-sm border transition-all',
                  halfDayPeriod === v
                    ? 'bg-blue-50 text-blue-600 border-blue-300'
                    : 'bg-white text-gray-500 border-gray-200',
                ].join(' ')}
              >
                {v === 'morning' ? '🌅 เช้า' : '🌇 บ่าย'}
              </button>
            ))}
          </div>
        )}

        {/* Date inputs */}
        <div className={isHalfDay ? '' : 'flex flex-col gap-3'}>
          <div>
            <label className="text-xs text-gray-500 mb-1 block">
              {isHalfDay ? 'วันที่' : 'วันเริ่ม'}
            </label>
            <input
              type="date"
              value={startDate}
              onChange={(e) => {
                setStartDate(e.target.value)
                if (e.target.value > endDate) setEndDate(e.target.value)
              }}
              className="w-full rounded-lg border border-gray-200 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-300"
            />
          </div>
          {!isHalfDay && (
            <div>
              <label className="text-xs text-gray-500 mb-1 block">วันสิ้นสุด</label>
              <input
                type="date"
                value={endDate}
                min={startDate}
                onChange={(e) => setEndDate(e.target.value)}
                className="w-full rounded-lg border border-gray-200 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-300"
              />
            </div>
          )}
        </div>

        {/* Days summary */}
        {days > 0 && (
          <div className="rounded-lg bg-blue-50 px-3 py-2 flex items-center justify-between">
            <span className="text-xs text-blue-600">จำนวนวันลา</span>
            <span className="text-sm font-semibold text-blue-700">{days} วัน</span>
          </div>
        )}
      </div>

      {/* เหตุผล */}
      <div>
        <label className="text-sm font-medium text-gray-700 mb-1 block">
          เหตุผล
          <span className="text-gray-400 font-normal ml-1">(ไม่บังคับ)</span>
        </label>
        <textarea
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          placeholder="ระบุเหตุผล..."
          rows={3}
          className="w-full rounded-lg border border-gray-200 px-3 py-2 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-blue-300"
        />
      </div>

      {/* Attachment (ลาป่วย 3+ วัน) */}
      {selectedType === 'sick' && days >= 3 && (
        <div>
          <label className="text-sm font-medium text-gray-700 mb-1 block">
            URL ใบรับรองแพทย์
            <span className="text-red-500 ml-1">*</span>
          </label>
          <input
            type="url"
            value={attachmentUrl}
            onChange={(e) => setAttachmentUrl(e.target.value)}
            placeholder="https://..."
            className="w-full rounded-lg border border-gray-200 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-300"
          />
        </div>
      )}

      {/* Approval routing */}
      <div className="rounded-lg bg-gray-50 px-3 py-2">
        <p className="text-xs text-gray-500">
          สายอนุมัติ: <span className="font-medium text-gray-700">{approvalLabel()}</span>
        </p>
      </div>

      {/* Submit */}
      <button
        onClick={handleSubmit}
        disabled={isSubmitting || days <= 0}
        className={[
          'w-full py-3.5 rounded-xl text-sm font-semibold transition-all',
          isSubmitting || days <= 0
            ? 'bg-gray-100 text-gray-400 cursor-not-allowed'
            : 'bg-blue-500 text-white active:scale-[0.98]',
        ].join(' ')}
      >
        {isSubmitting ? 'กำลังส่ง...' : `ส่งคำขอลา ${days > 0 ? `(${days} วัน)` : ''}`}
      </button>

    </div>
  )
}