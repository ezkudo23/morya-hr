// hooks/use-ot.ts
// หน้าที่: เรียก OT RPC functions — get_ot_requests, submit_ot_request, approve_ot_request

import { useState, useEffect, useCallback } from 'react'
import { createClient } from '@/lib/supabase/client'

// ─── Types ───────────────────────────────────────────────

export type OtType =
  | 'weekday_ot'
  | 'holiday_changed_ot'
  | 'holiday_substitute_work'
  | 'holiday_ot'

export const OT_TYPE_LABELS: Record<OtType, string> = {
  weekday_ot:               'OT วันทำงาน (1.5x)',
  holiday_changed_ot:       'OT วันหยุดชดเชย (3x)',
  holiday_substitute_work:  'ทำงานวันหยุด (token)',
  holiday_ot:               'OT วันหยุด (3x)',
}

export interface OtRequest {
  id:               string
  employee_id:      string
  employee_code:    string
  employee_name:    string
  work_date:        string
  start_time:       string
  end_time:         string
  ot_hours:         number
  ot_type:          OtType
  rate_multiplier:  number
  reason:           string | null
  attachment_url:   string | null
  status:           'pending' | 'approved' | 'rejected' | 'cancelled'
  approver_chain:   object[]
  approver_note:    string | null
  approved_at:      string | null
  rejected_at:      string | null
  created_at:       string
}

export interface SubmitOtPayload {
  employee_id:      string
  work_date:        string   // YYYY-MM-DD
  start_time:       string   // HH:MM
  end_time:         string   // HH:MM
  reason?:          string
  attachment_url?:  string
}

export interface SubmitOtResult {
  success:          boolean
  ot_request_id?:   string
  ot_type?:         OtType
  ot_hours?:        number
  rate_multiplier?: number
  week_ot_total?:   number
  window_deadline?: string
  error?:           string
  detail?:          string
}

export interface ApproveOtPayload {
  ot_request_id: string
  approver_id:   string
  action:        'approve' | 'reject'
  note?:         string
}

export interface ApproveOtResult {
  success:        boolean
  action?:        string
  ot_request_id?: string
  ot_hours?:      number
  ot_type?:       OtType
  error?:         string
}

// ─── Hook ────────────────────────────────────────────────

export function useOt(employeeId: string) {
  const supabase = createClient()

  const [myOtRequests, setMyOtRequests] = useState<OtRequest[]>([])
  const [loading, setLoading]           = useState(false)
  const [submitting, setSubmitting]     = useState(false)
  const [approving, setApproving]       = useState(false)

  // ดึง OT history ของตัวเอง
  const fetchMyOt = useCallback(async () => {
    if (!employeeId) return
    setLoading(true)
    try {
      const { data, error } = await supabase.rpc('get_ot_requests', {
        p_employee_id: employeeId,
        p_role:        'staff',
      })
      if (error) throw error
      if (data?.success) setMyOtRequests(data.requests ?? [])
    } catch (err) {
      console.error('fetchMyOt error:', err)
    } finally {
      setLoading(false)
    }
  }, [employeeId, supabase])

  useEffect(() => {
    fetchMyOt()
  }, [fetchMyOt])

  // ขอ OT
  const submitOt = async (payload: SubmitOtPayload): Promise<SubmitOtResult> => {
    setSubmitting(true)
    try {
      const { data, error } = await supabase.rpc('submit_ot_request', {
        p_employee_id:    payload.employee_id,
        p_work_date:      payload.work_date,
        p_start_time:     payload.start_time,
        p_end_time:       payload.end_time,
        p_reason:         payload.reason ?? null,
        p_attachment_url: payload.attachment_url ?? null,
      })
      if (error) throw error
      if (data?.success) await fetchMyOt()
      return data as SubmitOtResult
    } catch (err) {
      return { success: false, error: 'UNEXPECTED_ERROR', detail: String(err) }
    } finally {
      setSubmitting(false)
    }
  }

  // Approve/Reject OT
  const approveOt = async (payload: ApproveOtPayload): Promise<ApproveOtResult> => {
    setApproving(true)
    try {
      const { data, error } = await supabase.rpc('approve_ot_request', {
        p_ot_request_id: payload.ot_request_id,
        p_approver_id:   payload.approver_id,
        p_action:        payload.action,
        p_note:          payload.note ?? null,
      })
      if (error) throw error
      return data as ApproveOtResult
    } catch (err) {
      return { success: false, error: 'UNEXPECTED_ERROR' }
    } finally {
      setApproving(false)
    }
  }

  return {
    myOtRequests,
    loading,
    submitting,
    approving,
    fetchMyOt,
    submitOt,
    approveOt,
  }
}