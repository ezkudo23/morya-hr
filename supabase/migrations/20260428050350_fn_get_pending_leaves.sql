-- Function: get_pending_leaves
-- หน้าที่: ดึง leave requests ที่รออนุมัติ สำหรับ Supervisor/HR/Owner
-- Security: SECURITY DEFINER (bypass RLS)
-- Date: 28 เม.ย. 2569

CREATE OR REPLACE FUNCTION get_pending_leaves(
  p_approver_id UUID  -- auth.users.id ของ approver
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_approver  RECORD;
  v_results   JSONB;
BEGIN

  -- ดึง role ของ approver
  SELECT p.role, p.employee_id
  INTO v_approver
  FROM profiles p
  WHERE p.id = p_approver_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'APPROVER_NOT_FOUND');
  END IF;

  -- ดึง pending leaves ตาม role
  SELECT jsonb_agg(
    jsonb_build_object(
      'id',               lr.id,
      'employee_id',      lr.employee_id,
      'employee_code',    e.employee_code,
      'employee_name',    COALESCE(e.nickname, e.first_name),
      'leave_type',       lr.leave_type,
      'start_date',       lr.start_date,
      'end_date',         lr.end_date,
      'days',             lr.days,
      'is_half_day',      lr.is_half_day,
      'half_day_period',  lr.half_day_period,
      'reason',           lr.reason,
      'attachment_url',   lr.attachment_url,
      'is_backdate',      lr.is_backdate,
      'approval_step',    lr.approval_step,
      'approval_step_max',lr.approval_step_max,
      'approver_chain',   lr.approver_chain,
      'created_at',       lr.created_at
    )
    ORDER BY lr.created_at ASC
  )
  INTO v_results
  FROM leave_requests lr
  JOIN employees e ON e.id = lr.employee_id
  WHERE lr.status = 'pending'
    AND lr.current_approver_id = p_approver_id
    -- Owner/Delegate เห็นทุก pending
    OR (
      v_approver.role IN ('owner', 'owner_delegate')
      AND lr.status = 'pending'
    );

  RETURN jsonb_build_object(
    'success', true,
    'role',    v_approver.role,
    'leaves',  COALESCE(v_results, '[]'::jsonb)
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

GRANT EXECUTE ON FUNCTION get_pending_leaves TO authenticated;