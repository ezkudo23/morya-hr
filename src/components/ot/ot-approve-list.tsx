// components/ot/ot-approve-list.tsx
// หน้าที่: Supervisor/HR/Owner ดู pending OT + approve/reject

'use client'

import { useState, useEffect, useCallback } from 'react'
import { createClient } from '@/lib/supabase/client'
import { OT_TYPE_LABELS, OtRequest, ApproveOtPayload, ApproveOtResult } from '@/hooks/use-ot'

interface OtApproveListProps {
  approverId:  string
  onApprove:   (payload: ApproveOtPayload) => Promise<ApproveOtResult>
  isApproving: boolean
}

export function OtApproveList({ approverId, onApprove, isApproving }: OtApproveListProps) {
  const supabase = createClient()

  const [requests,   setRequests]   = useState<OtRequest[]>([])
  const [loading,    setLoading]    = useState(true)
  const [selected,   setSelected]   = useState<OtRequest | null>(null)
  const [note,       setNote]       = useState('')
  const [actionDone, setActionDone] = useState<'approved' | 'rejected' | null>(null)

  const toThaiDate = (dateStr: string) =>
    new Date(dateStr).toLocaleDateString('th-TH', {
      year: 'numeric', month: 'long', day: 'numeric',
    })

  const fetchPending = useCallback(async () => {
    setLoading(true)
    try {
      const { data, error } = await supabase.rpc('get_ot_requests', {
        p_approver_id: approverId,
        p_role:        'approver',
      })
      if (error) throw error
      if (data?.success) setRequests(data.requests ?? [])
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
      ot_request_id: selected.id,
      approver_id:   approverId,
      action,
      note:          note || undefined,
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

  // ─── Loading ───────────────────────────────────
  if (loading) {
    return (
      <p className="text-sm text-gray-400 text-center py-8">กำลังโหลด...</p>
    )
  }

  // ─── Detail view ───────────────────────────────
  if (selected) {
    if (actionDone) {
      return (
        <div className="text-center py-12 space-y-2">
          <p className="text-3xl">{actionDone === 'approved' ? '✅' : '❌'}</p>
          <p className="text-sm font-medium text-gray-700">
            {actionDone === 'approved' ? 'อนุมัติแล้ว' : 'ไม่อนุมัติ'}
          </p>
        </div>
      )
    }

    return (
      <div className="space-y-4">

        {/* Back */}
        <button
          onClick={() => { setSelected(null); setNote('') }}
          className="flex items-center gap-1.5 text-xs text-gray-400"
        >
          ← กลับ
        </button>

        {/* Card */}
        <div className="bg-white border border-gray-200 rounded-2xl px-5 py-4 space-y-3">
          <div className="flex items-center justify-between">
            <span className="text-sm font-semibold text-gray-900">
              {selected.employee_name}
            </span>
            <span className="text-xs text-gray-400">{selected.employee_code}</span>
          </div>

          <div className="space-y-1.5 text-xs text-gray-600">
            <div className="flex justify-between">
              <span className="text-gray-400">วันที่</span>
              <span>{toThaiDate(selected.work_date)}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-400">เวลา</span>
              <span>{selected.start_time.slice(0,5)}–{selected.end_time.slice(0,5)}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-400">รวม</span>
              <span className="font-semibold text-gray-900">{selected.ot_hours} ชม.</span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-400">ประเภท</span>
              <span>{OT_TYPE_LABELS[selected.ot_type]}</span>
            </div>
            {selected.reason && (
              <div className="flex justify-between">
                <span className="text-gray-400">เหตุผล</span>
                <span className="text-right max-w-[60%]">{selected.reason}</span>
              </div>
            )}
          </div>
        </div>

        {/* Note */}
        <div className="space-y-1.5">
          <label className="text-xs font-medium text-gray-500">
            หมายเหตุ <span className="text-gray-400">(ไม่บังคับ)</span>
          </label>
          <textarea
            value={note}
            onChange={e => setNote(e.target.value)}
            placeholder="ระบุเหตุผลถ้าไม่อนุมัติ..."
            rows={2}
            className="w-full border border-gray-200 rounded-xl px-4 py-3 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-300 resize-none"
          />
        </div>

        {/* Actions */}
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

  // ─── Empty ─────────────────────────────────────
  if (requests.length === 0) {
    return (
      <div className="text-center py-12 space-y-2">
        <p className="text-2xl">✅</p>
        <p className="text-sm text-gray-400">ไม่มีคำขอ OT รออนุมัติ</p>
      </div>
    )
  }

  // ─── List ──────────────────────────────────────
  return (
    <div className="space-y-3">
      <p className="text-xs text-gray-400">รออนุมัติ {requests.length} รายการ</p>
      {requests.map(ot => (
        <button
          key={ot.id}
          onClick={() => setSelected(ot)}
          className="w-full text-left bg-white border border-gray-200 rounded-xl px-4 py-3 space-y-2 active:scale-[0.98] transition-all"
        >
          <div className="flex items-center justify-between">
            <span className="text-sm font-medium text-gray-900">
              {ot.employee_name}
            </span>
            <span className="text-xs text-amber-600 font-medium bg-amber-50 px-2 py-0.5 rounded-full">
              รออนุมัติ
            </span>
          </div>
          <div className="flex items-center justify-between">
            <span className="text-xs text-gray-500">
              {new Date(ot.work_date).toLocaleDateString('th-TH', { month: 'short', day: 'numeric' })}
              {' · '}{ot.start_time.slice(0,5)}–{ot.end_time.slice(0,5)}
              {' · '}{ot.ot_hours} ชม.
            </span>
            <span className="text-xs text-gray-400">
              {OT_TYPE_LABELS[ot.ot_type]}
            </span>
          </div>
        </button>
      ))}
    </div>
  )
}