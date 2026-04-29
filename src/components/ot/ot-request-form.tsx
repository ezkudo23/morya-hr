// components/ot/ot-request-form.tsx
// หน้าที่: Staff กรอกฟอร์มขอ OT

'use client'

import { useState } from 'react'
import { OT_TYPE_LABELS, SubmitOtPayload, SubmitOtResult } from '@/hooks/use-ot'

interface OtRequestFormProps {
  employeeId:   string
  onSubmit:     (payload: SubmitOtPayload) => Promise<SubmitOtResult>
  isSubmitting: boolean
}

const ERROR_MESSAGES: Record<string, string> = {
  PC_NO_OT:                'PC ไม่มีสิทธิ์ขอ OT',
  INVALID_TIME_RANGE:      'เวลาไม่ถูกต้อง — กรุณาตรวจสอบ',
  OT_EXCEEDS_12HR_PER_DAY: 'OT เกิน 12 ชม./วัน ไม่ได้',
  OT_WINDOW_EXPIRED:       'เกิน 72 ชม.หลังทำงาน — ขอย้อนหลังไม่ได้',
  OT_WEEKLY_CAP_EXCEEDED:  'OT สัปดาห์นี้เต็ม 36 ชม.แล้ว',
  OT_DUPLICATE_OVERLAP:    'มีคำขอ OT ช่วงเวลานี้อยู่แล้ว',
  UNEXPECTED_ERROR:        'เกิดข้อผิดพลาด — กรุณาลองใหม่',
}

export function OtRequestForm({ employeeId, onSubmit, isSubmitting }: OtRequestFormProps) {
  const today = new Date().toISOString().split('T')[0]

  const [workDate,  setWorkDate]  = useState(today)
  const [startTime, setStartTime] = useState('')
  const [endTime,   setEndTime]   = useState('')
  const [reason,    setReason]    = useState('')
  const [result,    setResult]    = useState<SubmitOtResult | null>(null)

  const hours = (() => {
    if (!startTime || !endTime) return 0
    const [sh, sm] = startTime.split(':').map(Number)
    const [eh, em] = endTime.split(':').map(Number)
    const diff = (eh * 60 + em) - (sh * 60 + sm)
    return diff > 0 ? Math.round(diff / 60 * 10) / 10 : 0
  })()

  const thaiDate = (dateStr: string) =>
    new Date(dateStr).toLocaleDateString('th-TH', {
      year: 'numeric', month: 'long', day: 'numeric', weekday: 'long',
    })

  const handleSubmit = async () => {
    if (!workDate || !startTime || !endTime) return
    const res = await onSubmit({
      employee_id: employeeId,
      work_date:   workDate,
      start_time:  startTime,
      end_time:    endTime,
      reason:      reason || undefined,
    })
    setResult(res)
    if (res.success) {
      setStartTime('')
      setEndTime('')
      setReason('')
    }
  }

  // ─── Success ─────────────────────────────────
  if (result?.success) {
    return (
      <div className="bg-green-50 border border-green-200 rounded-2xl px-5 py-6 text-center space-y-2">
        <p className="text-2xl">✅</p>
        <p className="text-sm font-semibold text-green-800">ส่งคำขอ OT สำเร็จ</p>
        <p className="text-xs text-green-600">
          {result.ot_hours} ชม.
          {result.ot_type ? ` · ${OT_TYPE_LABELS[result.ot_type]}` : ''}
        </p>
        <p className="text-xs text-green-500">
          OT สัปดาห์นี้รวม {result.week_ot_total} ชม.
        </p>
        <button
          onClick={() => setResult(null)}
          className="mt-3 text-xs text-green-700 underline"
        >
          ขอ OT เพิ่ม
        </button>
      </div>
    )
  }

  // ─── Form ─────────────────────────────────────
  return (
    <div className="space-y-4">

      {/* Error */}
      {result && !result.success && (
        <div className="bg-red-50 border border-red-200 rounded-xl px-4 py-3">
          <p className="text-sm font-medium text-red-700">
            {ERROR_MESSAGES[result.error ?? ''] ?? result.error}
          </p>
          {result.error === 'OT_WEEKLY_CAP_EXCEEDED' && (
            <p className="text-xs text-red-500 mt-1">
              ขอได้อีกสูงสุด {36 - ((result as any).current_week_ot ?? 0)} ชม.สัปดาห์นี้
            </p>
          )}
        </div>
      )}

      {/* วันที่ */}
      <div className="space-y-1.5">
        <label className="text-xs font-medium text-gray-500">วันที่ทำ OT</label>
        <input
          type="date"
          value={workDate}
          max={today}
          onChange={e => setWorkDate(e.target.value)}
          className="w-full border border-gray-200 rounded-xl px-4 py-3 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-300 appearance-none"
        />
        {workDate && (
          <p className="text-xs text-gray-400 px-1">
            {thaiDate(workDate)}
          </p>
        )}
      </div>

      {/* เวลา */}
      <div className="grid grid-cols-2 gap-2">
        <div className="space-y-1.5">
          <label className="text-xs font-medium text-gray-500">เวลาเริ่ม</label>
          <input
            type="time"
            value={startTime}
            onChange={e => setStartTime(e.target.value)}
            className="w-full border border-gray-200 rounded-xl px-3 py-3 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-300"
          />
        </div>
        <div className="space-y-1.5">
          <label className="text-xs font-medium text-gray-500">เวลาสิ้นสุด</label>
          <input
            type="time"
            value={endTime}
            onChange={e => setEndTime(e.target.value)}
            className="w-full border border-gray-200 rounded-xl px-3 py-3 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-300"
          />
        </div>
      </div>

      {/* แสดงชั่วโมง */}
      {hours > 0 && (
        <div className="bg-blue-50 rounded-xl px-4 py-2.5 flex items-center justify-between">
          <span className="text-xs text-blue-600">รวม OT</span>
          <span className="text-sm font-semibold text-blue-700">{hours} ชม.</span>
        </div>
      )}

      {/* เหตุผล */}
      <div className="space-y-1.5">
        <label className="text-xs font-medium text-gray-500">
          เหตุผล <span className="text-gray-400">(ไม่บังคับ)</span>
        </label>
        <textarea
          value={reason}
          onChange={e => setReason(e.target.value)}
          placeholder="ระบุเหตุผลการทำ OT..."
          rows={3}
          className="w-full border border-gray-200 rounded-xl px-4 py-3 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-300 resize-none"
        />
      </div>

      {/* Submit */}
      <button
        onClick={handleSubmit}
        disabled={isSubmitting || !workDate || !startTime || !endTime || hours <= 0}
        className={[
          'w-full py-3.5 rounded-xl text-sm font-semibold transition-all',
          isSubmitting || !workDate || !startTime || !endTime || hours <= 0
            ? 'bg-gray-100 text-gray-400 cursor-not-allowed'
            : 'bg-blue-500 text-white active:scale-[0.98]',
        ].join(' ')}
      >
        {isSubmitting ? 'กำลังส่ง...' : `ส่งคำขอ OT${hours > 0 ? ` (${hours} ชม.)` : ''}`}
      </button>

    </div>
  )
}