-- Function: get_ot_requests
-- หน้าที่: ดึง OT requests — ใช้ได้ทั้ง staff (ประวัติตัวเอง) และ approver (pending list)
-- Security: SECURITY DEFINER (bypass RLS)
-- Date: 29 เม.ย. 2569

CREATE OR REPLACE FUNCTION get_ot_requests(
  p_employee_id   UUID    DEFAULT NULL,  -- ถ้าระบุ = ดึงของคนนี้
  p_approver_id   UUID    DEFAULT NULL,  -- ถ้าระบุ = ดึง pending ที่รอ approve
  p_status        TEXT    DEFAULT NULL,  -- filter by status
  p_month         INTEGER DEFAULT NULL,  -- filter by month
  p_year          INTEGER DEFAULT EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER,
  p_limit         INTEGER DEFAULT 50,
  p_offset        INTEGER DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_approver  RECORD;
  v_results   JSONB;
  v_total     INTEGER;
  v_monthly_hours DECIMAL(4,1);
BEGIN

  -- ดึง role ของ approver (ถ้ามี)
  IF p_approver_id IS NOT NULL THEN
    SELECT p.role, p.employee_id
    INTO v_approver
    FROM profiles p
    WHERE p.id = p_approver_id;
  END IF;

  -- นับ total
  SELECT COUNT(*)
  INTO v_total
  FROM ot_requests ot
  WHERE (
    -- staff mode: ดึงของตัวเอง
    (p_employee_id IS NOT NULL AND ot.employee_id = p_employee_id)
    OR
    -- approver mode: ดึง pending ที่รอ approve
    (p_approver_id IS NOT NULL AND ot.status = 'pending' AND (
      ot.current_approver_id = p_approver_id
      OR v_approver.role IN ('owner', 'owner_delegate')
    ))
  )
  AND (p_status IS NULL OR ot.status = p_status)
  AND EXTRACT(YEAR FROM ot.ot_date) = p_year
  AND (p_month IS NULL OR EXTRACT(MONTH FROM ot.ot_date) = p_month);

  -- ดึงรายการ
  SELECT jsonb_agg(
    jsonb_build_object(
      'id',                   ot.id,
      'employee_id',          ot.employee_id,
      'employee_name',        COALESCE(e.nickname, e.full_name_th),
      'employee_code',        e.employee_code,
      'ot_date',              ot.ot_date,
      'start_time',           ot.start_time,
      'end_time',             ot.end_time,
      'hours',                ot.hours,
      'ot_type',              ot.ot_type,
      'rate_multiplier',      ot.rate_multiplier,
      'hourly_rate',          ot.hourly_rate,
      'is_fixed_rate',        ot.is_fixed_rate,
      'reason',               ot.reason,
      'evidence_url',         ot.evidence_url,
      'status',               ot.status,
      'approval_step',        ot.approval_step,
      'approval_step_max',    ot.approval_step_max,
      'approver_chain',       ot.approver_chain,
      'approver_note',        ot.approver_note,
      'approved_at',          ot.approved_at,
      'rejected_at',          ot.rejected_at,
      'submitted_within_window', ot.submitted_within_window,
      'is_backdate',          ot.is_backdate,
      'created_at',           ot.created_at
    )
    ORDER BY ot.ot_date DESC, ot.created_at DESC
  )
  INTO v_results
  FROM ot_requests ot
  JOIN employees e ON e.id = ot.employee_id
  WHERE (
    (p_employee_id IS NOT NULL AND ot.employee_id = p_employee_id)
    OR
    (p_approver_id IS NOT NULL AND ot.status = 'pending' AND (
      ot.current_approver_id = p_approver_id
      OR v_approver.role IN ('owner', 'owner_delegate')
    ))
  )
  AND (p_status IS NULL OR ot.status = p_status)
  AND EXTRACT(YEAR FROM ot.ot_date) = p_year
  AND (p_month IS NULL OR EXTRACT(MONTH FROM ot.ot_date) = p_month)
  LIMIT p_limit
  OFFSET p_offset;

  -- Monthly hours summary (สำหรับ staff mode)
  IF p_employee_id IS NOT NULL THEN
    SELECT COALESCE(SUM(hours), 0)
    INTO v_monthly_hours
    FROM ot_requests
    WHERE employee_id = p_employee_id
      AND status IN ('pending', 'approved')
      AND EXTRACT(YEAR  FROM ot_date) = p_year
      AND (p_month IS NULL OR EXTRACT(MONTH FROM ot_date) = p_month);
  END IF;

  RETURN jsonb_build_object(
    'success',        true,
    'total',          v_total,
    'year',           p_year,
    'requests',       COALESCE(v_results, '[]'::jsonb),
    'monthly_hours',  COALESCE(v_monthly_hours, 0),
    'max_monthly',    36
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

GRANT EXECUTE ON FUNCTION get_ot_requests TO authenticated;