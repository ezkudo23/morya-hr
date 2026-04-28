-- Function: get_leave_history
-- หน้าที่: ดึงประวัติคำขอลาของพนักงาน 1 คน
-- Security: SECURITY DEFINER (bypass RLS)
-- Date: 28 เม.ย. 2569

CREATE OR REPLACE FUNCTION get_leave_history(
  p_employee_id UUID,
  p_year        INTEGER DEFAULT EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER,
  p_limit       INTEGER DEFAULT 20,
  p_offset      INTEGER DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_results   JSONB;
  v_total     INTEGER;
BEGIN

  -- นับ total
  SELECT COUNT(*)
  INTO v_total
  FROM leave_requests
  WHERE employee_id = p_employee_id
    AND EXTRACT(YEAR FROM start_date) = p_year;

  -- ดึงรายการ
  SELECT jsonb_agg(
    jsonb_build_object(
      'id',               lr.id,
      'leave_type',       lr.leave_type,
      'start_date',       lr.start_date,
      'end_date',         lr.end_date,
      'days',             lr.days,
      'is_half_day',      lr.is_half_day,
      'half_day_period',  lr.half_day_period,
      'reason',           lr.reason,
      'status',           lr.status,
      'is_backdate',      lr.is_backdate,
      'approval_step',    lr.approval_step,
      'approval_step_max',lr.approval_step_max,
      'approver_chain',   lr.approver_chain,
      'approver_note',    lr.approver_note,
      'approved_at',      lr.approved_at,
      'rejected_at',      lr.rejected_at,
      'created_at',       lr.created_at
    )
    ORDER BY lr.created_at DESC
  )
  INTO v_results
  FROM leave_requests lr
  WHERE lr.employee_id = p_employee_id
    AND EXTRACT(YEAR FROM lr.start_date) = p_year
  LIMIT p_limit
  OFFSET p_offset;

  RETURN jsonb_build_object(
    'success', true,
    'total',   v_total,
    'year',    p_year,
    'history', COALESCE(v_results, '[]'::jsonb)
  );

EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'success', false,
      'error',   'UNEXPECTED_ERROR',
      'detail',  SQLERRM
    );
END;
$$;

GRANT EXECUTE ON FUNCTION get_leave_history TO authenticated;