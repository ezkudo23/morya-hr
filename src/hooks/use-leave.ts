// hooks/use-leave.ts
// หน้าที่: เรียก Leave RPC functions ทั้ง 3 — get_leave_balance, submit_leave_request, approve_leave_request

import { useState, useEffect, useCallback } from 'react'
import { createClient } from '@/lib/supabase/client'

// ─── Types ───────────────────────────────────────────────

export type LeaveType =
  | 'annual'
  | 'sick'
  | 'personal'
  | 'maternity'
  | 'ordination'
  | 'marriage'
  | 'funeral'
  | 'military'
  | 'training'

export const LEAVE_TYPE_LABELS: Record<LeaveType, string> = {
  annual:     'ลาพักร้อน',
  sick:       'ลาป่วย',
  personal:   'ลากิจ',
  maternity:  'ลาคลอด',
  ordination: 'ลาบวช',
  marriage:   'ลาสมรส',
  funeral:    'ลาฌาปนกิจ',
  military:   'ลาทหาร',
  training:   'ลาฝึกอบรม',
}

export const LEAVE_TYPE_QUOTA: Record<LeaveType, string> = {
  annual:     '6 วัน/ปี',
  sick:       '30 วัน/ปี',
  personal:   '3 วัน/ปี',
  maternity:  '45+45 วัน',
  ordination: '15 วัน',
  marriage:   '3 วัน',
  funeral:    '5 วัน',
  military:   'ตามหมายเรียก',
  training:   '30 วัน/ปี',
}

export interface LeaveBalance {
  leave_type:          LeaveType
  entitled_days:       number
  used_days:           number
  remaining_days:      number
  available:           boolean
  unavailable_reason:  string | null
  supports_half_day:   boolean
  supports_backdate:   boolean
}

export interface LeaveBalanceResult {
  success:      boolean
  employee_id:  string
  year:         number
  is_probation: boolean
  balances:     LeaveBalance[]
  pending:      Record<LeaveType, number>
  error?:       string
}

export interface SubmitLeavePayload {
  employee_id:      string
  leave_type:       LeaveType
  start_date:       string   // YYYY-MM-DD
  end_date:         string   // YYYY-MM-DD
  is_half_day?:     boolean
  half_day_period?: 'morning' | 'afternoon'
  reason?:          string
  attachment_url?:  string
  is_backdate?:     boolean
}

export interface SubmitLeaveResult {
  success:            boolean
  leave_request_id?:  string
  days?:              number
  approval_step_max?: number
  triggers_diligence?: boolean
  advance_notice_met?: boolean
  is_probation?:      boolean
  error?:             string
  hint?:              string
  remaining?:         number
  requested?:         number
}

export interface ApproveLeavePayload {
  leave_request_id: string
  approver_id:      string
  action:           'approve' | 'reject'
  note?:            string
}

export interface ApproveLeaveResult {
  success:            boolean
  action?:            'advanced' | 'final_approved' | 'rejected'
  next_step?:         number
  next_approver_id?:  string
  leave_request_id?:  string
  days_deducted?:     number
  diligence_updated?: boolean
  error?:             string
  status?:            string
}

// ─── Hook ────────────────────────────────────────────────

export function useLeave(employeeId: string | null) {
  const supabase = createClient()

  const [balance, setBalance]         = useState<LeaveBalanceResult | null>(null)
  const [loadingBalance, setLoadingBalance] = useState(false)
  const [submitting, setSubmitting]   = useState(false)
  const [approving, setApproving]     = useState(false)
  const [error, setError]             = useState<string | null>(null)

  // ─── get_leave_balance ──────────────────────────
  const fetchBalance = useCallback(async (year?: number) => {
    if (!employeeId) return

    setLoadingBalance(true)
    setError(null)

    try {
      const { data, error: rpcError } = await supabase.rpc('get_leave_balance', {
        p_employee_id: employeeId,
        ...(year ? { p_year: year } : {}),
      })

      if (rpcError) throw rpcError

      setBalance(data as LeaveBalanceResult)
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'เกิดข้อผิดพลาด'
      setError(message)
    } finally {
      setLoadingBalance(false)
    }
  }, [employeeId, supabase])

  // โหลด balance อัตโนมัติเมื่อมี employeeId
  useEffect(() => {
    if (employeeId) fetchBalance()
  }, [employeeId, fetchBalance])

  // ─── submit_leave_request ───────────────────────
  const submitLeave = useCallback(async (
    payload: SubmitLeavePayload
  ): Promise<SubmitLeaveResult> => {
    setSubmitting(true)
    setError(null)

    try {
      const { data, error: rpcError } = await supabase.rpc('submit_leave_request', {
        p_employee_id:     payload.employee_id,
        p_leave_type:      payload.leave_type,
        p_start_date:      payload.start_date,
        p_end_date:        payload.end_date,
        p_is_half_day:     payload.is_half_day     ?? false,
        p_half_day_period: payload.half_day_period ?? null,
        p_reason:          payload.reason          ?? null,
        p_attachment_url:  payload.attachment_url  ?? null,
        p_is_backdate:     payload.is_backdate      ?? false,
      })

      if (rpcError) throw rpcError

      const result = data as SubmitLeaveResult

      // refresh balance หลัง submit สำเร็จ
      if (result.success) await fetchBalance()

      return result
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'เกิดข้อผิดพลาด'
      setError(message)
      return { success: false, error: message }
    } finally {
      setSubmitting(false)
    }
  }, [supabase, fetchBalance])

  // ─── approve_leave_request ──────────────────────
  const approveLeave = useCallback(async (
    payload: ApproveLeavePayload
  ): Promise<ApproveLeaveResult> => {
    setApproving(true)
    setError(null)

    try {
      const { data, error: rpcError } = await supabase.rpc('approve_leave_request', {
        p_leave_request_id: payload.leave_request_id,
        p_approver_id:      payload.approver_id,
        p_action:           payload.action,
        p_note:             payload.note ?? null,
      })

      if (rpcError) throw rpcError

      return data as ApproveLeaveResult
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'เกิดข้อผิดพลาด'
      setError(message)
      return { success: false, error: message }
    } finally {
      setApproving(false)
    }
  }, [supabase])

  return {
    // state
    balance,
    loadingBalance,
    submitting,
    approving,
    error,
    // actions
    fetchBalance,
    submitLeave,
    approveLeave,
  }
}