-- Function: get_leave_balance
-- หน้าที่: ดึง leave balance ทุกประเภทของพนักงาน 1 คน
-- Security: SECURITY DEFINER (bypass RLS)
-- Date: 27 เม.ย. 2569

CREATE OR REPLACE FUNCTION get_leave_balance(
  p_employee_id UUID,
  p_year        INTEGER DEFAULT EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_employee    RECORD;
  v_is_probation BOOLEAN;
  v_balances    JSONB;
  v_pending_days JSONB;
BEGIN

  -- ────────────────────────────────────────────
  -- 1. ดึงข้อมูลพนักงาน
  -- ────────────────────────────────────────────
  SELECT e.id, e.hire_date, p.role
  INTO v_employee
  FROM employees e
  JOIN profiles p ON p.employee_id = e.id
  WHERE e.id = p_employee_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'EMPLOYEE_NOT_FOUND');
  END IF;

  -- ────────────────────────────────────────────
  -- 2. Probation check
  -- ────────────────────────────────────────────
  v_is_probation := (
    v_employee.hire_date IS NOT NULL
    AND CURRENT_DATE < (v_employee.hire_date + INTERVAL '119 days')::DATE
  );

  -- ────────────────────────────────────────────
  -- 3. ดึง balance ทุกประเภท
  -- ────────────────────────────────────────────
  SELECT jsonb_agg(
    jsonb_build_object(
      'leave_type',      lb.leave_type,
      'entitled_days',   lb.entitled_days,
      'used_days',       lb.used_days,
      'remaining_days',  lb.remaining_days,
      -- flag ว่าใช้ได้ไหมในสถานะปัจจุบัน
      'available',       CASE
        WHEN v_is_probation AND lb.leave_type IN ('annual', 'personal') THEN false
        ELSE lb.remaining_days > 0
      END,
      -- เหตุผลที่ใช้ไม่ได้ (ถ้ามี)
      'unavailable_reason', CASE
        WHEN v_is_probation AND lb.leave_type = 'annual'   THEN 'PROBATION_NO_ANNUAL'
        WHEN v_is_probation AND lb.leave_type = 'personal' THEN 'PROBATION_NO_PERSONAL'
        WHEN lb.remaining_days <= 0                         THEN 'QUOTA_EXHAUSTED'
        ELSE NULL
      END,
      -- half-day support
      'supports_half_day', CASE
        WHEN lb.leave_type IN ('annual', 'sick', 'personal') THEN true
        ELSE false
      END,
      -- backdate support
      'supports_backdate', CASE
        WHEN lb.leave_type = 'sick' THEN true
        ELSE false
      END
    )
    ORDER BY CASE lb.leave_type
      WHEN 'annual'     THEN 1
      WHEN 'sick'       THEN 2
      WHEN 'personal'   THEN 3
      WHEN 'maternity'  THEN 4
      WHEN 'ordination' THEN 5
      WHEN 'marriage'   THEN 6
      WHEN 'funeral'    THEN 7
      WHEN 'military'   THEN 8
      WHEN 'training'   THEN 9
      ELSE 10
    END
  )
  INTO v_balances
  FROM leave_balances lb
  WHERE lb.employee_id = p_employee_id
    AND lb.year = p_year;

  -- ────────────────────────────────────────────
  -- 4. ดึง pending days (คำขอที่ยังไม่ approved)
  -- ────────────────────────────────────────────
  SELECT jsonb_object_agg(
    leave_type,
    pending_days
  )
  INTO v_pending_days
  FROM (
    SELECT
      leave_type,
      SUM(days) AS pending_days
    FROM leave_requests
    WHERE employee_id = p_employee_id
      AND status = 'pending'
      AND EXTRACT(YEAR FROM start_date) = p_year
    GROUP BY leave_type
  ) sub;

  -- ────────────────────────────────────────────
  -- 5. Return
  -- ────────────────────────────────────────────
  RETURN jsonb_build_object(
    'success',       true,
    'employee_id',   p_employee_id,
    'year',          p_year,
    'is_probation',  v_is_probation,
    'balances',      COALESCE(v_balances, '[]'::jsonb),
    'pending',       COALESCE(v_pending_days, '{}'::jsonb)
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

-- Grant execute
GRANT EXECUTE ON FUNCTION get_leave_balance TO authenticated;