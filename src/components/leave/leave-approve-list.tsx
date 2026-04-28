// components/leave/leave-approve-list.tsx
// หน้าที่: Supervisor/HR/Owner ดู pending leaves + approve/reject

'use client'

import { useState, useEffect, useCallback } from 'react'
import { createClient } from '@/lib/supabase/client'
import { LEAVE_TYPE_LABELS, LeaveType, ApproveLeavePayload, ApproveLeaveResult } from '@/hooks/use-leave'

interface PendingLeave {
  id:                string
  employee_id:       string
  employee_code:     string
  employee_name:     string
  leave_type:        LeaveType
  start_date:        string
  end_date:          string
  days:              number
  is_half_day:       boolean
  half_day_period:   'morning' | 'afternoon' | null
  reason:            string | null
  attachment_url:    string | null
  is_backdate:       boolean
  approval_step:     number
  approval_step_max: number
  approver_chain:    object[]
  created_at:        string
}

interface LeaveApproveListProps {
  approverId:  string
  onApprove:   (payload: ApproveLeavePayload) => Promise<ApproveLeaveResult>
  isApproving: boolean
}

export function LeaveApproveList({
  approverId,
  onApprove,
  isApproving,
}: LeaveApproveListProps) {
  const supabase = createClient()

  const [leaves,     setLeaves]     = useState<PendingLeave[]>([])
  const [loading,    setLoading]    = useState(true)
  const [selected,   setSelected]   = useState<PendingLeave | null>(null)
  const [note,       setNote]       = useState('')
  const [actionDone, setActionDone] = useState<'approved' | 'rejected' | null>(null)

  const toThaiDate = (dateStr: string) =>
    new Date(dateStr).toLocaleDateString('th-TH', {
      year: 'numeric', month: 'long', day: 'numeric',
    })

  const stepLabel = (step: number) => {
    if (step === 1) return 'Supervisor'
    if (step === 2) return 'HR Admin'
    return 'Owner'
  }

  const fetchPending = useCallback(async () => {
    setLoading(true)
    try {
      const { data, error } = await supabase.rpc('get_pending_leaves', {
        p_approver_id: approverId,
      })
      if (error) throw error
      if (data?.success) setLeaves(data.leaves ?? [])
    } catch (err) {
      console.error(err)
    } finally {
      setLoading(false)
    }
  }, [approverId, supabase])

  useEffect(() => {
    fetchPending()
  }, [fetchPending])

  const handleAction = async (action: 'approve' | 'reject') => {
    if (!selected) return
    const res = await onApprove({
      leave_request_id: selected.id,
      approver_id:      approverId,
      action,
      note:             note || undefined,
    })
    if (res.success) {
      setActionDone(action === 'approve' ? 'approved' : 'rejected')
      setTimeout(() => {
        setSelected(null)
        setNote('')
        setActionDone(null)
        fetchPending()
      }, 1500)
    }
  }

  if (loading) {
    return (
      <div className="space-y-3">
        {Array.from({ length: 2 }).map((_, i) => (
          <div key={i} className="h-24 rounded-xl bg-gray-100 animate-pulse" />
        ))}
      </div>
    )
  }

  if (leaves.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center py-16 text-center space-y-2">
        <div className="text-4xl">OK</div>
        <p className="text-sm font-medium text-gray-700">ไม่มีคำขอลารออนุมัติ</p>
        <p className="text-xs text-gray-400">ทุกคำขอได้รับการดำเนินการแล้ว</p>
      </div>
    )
  }

  if (selected) {
    if (actionDone) {
      return (
        <div className="flex flex-col items-center justify-center py-16 text-center space-y-3">
          <p className="text-base font-semibold text-gray-900">
            {actionDone === 'approved' ? 'อนุมัติแล้ว' : 'ไม่อนุมัติแล้ว'}
          </p>
        </div>
      )
    }

    return (
      <div className="space-y-4">
        <div className="flex items-center justify-between">
          <h2 className="text-base font-semibold text-gray-900">รายละเอียดคำขอ</h2>
          <button
            onClick={() => { setSelected(null); setNote('') }}
            className="text-sm text-gray-400"
          >
            ย้อนกลับ
          </button>
        </div>

        <div className="bg-gray-50 rounded-xl px-4 py-3 space-y-2">
          <div className="flex justify-between">
            <span className="text-xs text-gray-500">พนักงาน</span>
            <span className="text-sm font-medium text-gray-900">
              {selected.employee_name} - {selected.employee_code}
            </span>
          </div>
          <div className="flex justify-between">
            <span className="text-xs text-gray-500">ประเภท</span>
            <span className="text-sm font-medium text-gray-900">
              {LEAVE_TYPE_LABELS[selected.leave_type]}
            </span>
          </div>
          <div className="flex justify-between">
            <span className="text-xs text-gray-500">วันที่</span>
            <span className="text-sm text-gray-900">
              {selected.is_half_day
                ? toThaiDate(selected.start_date) + ' (' + (selected.half_day_period === 'morning' ? 'เช้า' : 'บ่าย') + ')'
                : selected.start_date === selected.end_date
                  ? toThaiDate(selected.start_date)
                  : toThaiDate(selected.start_date) + ' - ' + toThaiDate(selected.end_date)
              }
            </span>
          </div>
          <div className="flex justify-between">
            <span className="text-xs text-gray-500">จำนวน</span>
            <span className="text-sm font-medium text-gray-900">{selected.days} วัน</span>
          </div>
          {selected.reason && (
            <div className="flex justify-between">
              <span className="text-xs text-gray-500">เหตุผล</span>
              <span className="text-sm text-gray-900 text-right max-w-[60%]">{selected.reason}</span>
            </div>
          )}
          {selected.is_backdate && (
            <div className="rounded-lg bg-purple-50 px-3 py-1.5">
              <p className="text-xs text-purple-700">ลาย้อนหลัง</p>
            </div>
          )}
          {selected.attachment_url && (
            <div className="flex justify-between items-center">
              <span className="text-xs text-gray-500">เอกสาร</span>
              <a
                href={selected.attachment_url}
                target="_blank"
                rel="noopener noreferrer"
                className="text-xs text-blue-500 underline"
              >
                ดูใบรับรองแพทย์
              </a>
            </div>
          )}
          <div className="flex justify-between">
            <span className="text-xs text-gray-500">ขั้นอนุมัติ</span>
            <span className="text-xs text-gray-600">
              Step {selected.approval_step}/{selected.approval_step_max} - {stepLabel(selected.approval_step)}
            </span>
          </div>
          <div className="flex justify-between">
            <span className="text-xs text-gray-500">ส่งเมื่อ</span>
            <span className="text-xs text-gray-500">{toThaiDate(selected.created_at)}</span>
          </div>
        </div>

        <div>
          <label className="text-sm font-medium text-gray-700 mb-1 block">
            หมายเหตุ
            <span className="text-gray-400 font-normal ml-1">(ไม่บังคับ)</span>
          </label>
          <textarea
            value={note}
            onChange={(e) => setNote(e.target.value)}
            placeholder="ระบุเหตุผลเพิ่มเติม..."
            rows={2}
            className="w-full rounded-lg border border-gray-200 px-3 py-2 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-blue-300"
          />
        </div>

        <div className="flex gap-3">
          <button
            onClick={() => handleAction('reject')}
            disabled={isApproving}
            className={[
              'flex-1 py-3.5 rounded-xl text-sm font-semibold border transition-all',
              isApproving
                ? 'bg-gray-50 text-gray-300 border-gray-100 cursor-not-allowed'
                : 'bg-white text-red-500 border-red-200 active:scale-[0.98]',
            ].join(' ')}
          >
            ไม่อนุมัติ
          </button>
          <button
            onClick={() => handleAction('approve')}
            disabled={isApproving}
            className={[
              'flex-1 py-3.5 rounded-xl text-sm font-semibold transition-all',
              isApproving
                ? 'bg-gray-100 text-gray-400 cursor-not-allowed'
                : 'bg-green-500 text-white active:scale-[0.98]',
            ].join(' ')}
          >
            {isApproving ? 'กำลังดำเนินการ...' : 'อนุมัติ'}
          </button>
        </div>
      </div>
    )
  }

  return (
    <div className="space-y-3">
      <p className="text-xs text-gray-400">
        รออนุมัติ {leaves.length} รายการ
      </p>
      {leaves.map((leave) => (
        <button
          key={leave.id}
          onClick={() => setSelected(leave)}
          className="w-full text-left bg-white border border-gray-200 rounded-xl px-4 py-3 space-y-2 active:scale-[0.98] transition-all"
        >
          <div className="flex items-center justify-between">
            <span className="text-sm font-medium text-gray-900">
              {leave.employee_name}
            </span>
            <span className="text-xs text-amber-600 font-medium bg-amber-50 px-2 py-0.5 rounded-full">
              รออนุมัติ
            </span>
          </div>
          <div className="flex items-center justify-between">
            <span className="text-xs text-gray-500">
              {LEAVE_TYPE_LABELS[leave.leave_type]} - {leave.days} วัน
            </span>
            <span className="text-xs text-gray-400">
              {toThaiDate(leave.start_date)}
            </span>
          </div>
          <div className="flex items-center gap-2">
            <span className="text-xs text-gray-400">
              Step {leave.approval_step}/{leave.approval_step_max}
            </span>
            {leave.is_backdate && (
              <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-purple-50 text-purple-500">
                ย้อนหลัง
              </span>
            )}
          </div>
        </button>
      ))}
    </div>
  )
}
