-- Function: submit_ot_request
-- หน้าที่: Staff ขอ OT — validate แล้ว insert
-- Security: SECURITY DEFINER (bypass RLS)
-- Date: 29 เม.ย. 2569

CREATE OR REPLACE FUNCTION submit_ot_request(
  p_employee_id   UUID,
  p_ot_date       DATE,
  p_start_time    TIME,
  p_end_time      TIME,
  p_ot_type       TEXT,
  p_reason        TEXT    DEFAULT NULL,
  p_evidence_url  TEXT    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_employee          RECORD;
  v_hours             DECIMAL(4,1);
  v_rate_multiplier   DECIMAL(4,2);
  v_hourly_rate       DECIMAL(10,2);
  v_is_fixed_rate     BOOLEAN;
  v_within_window     BOOLEAN;
  v_is_backdate       BOOLEAN;
  v_monthly_hours     DECIMAL(4,1);
  v_max_monthly_hours DECIMAL(4,1) := 36;
  v_first_approver_id UUID;
  v_new_id            UUID;
BEGIN

  -- ────────────────────────────────────────────
  -- 1. ดึงข้อมูลพนักงาน
  -- ────────────────────────────────────────────
  SELECT e.*, p.role
  INTO v_employee
  FROM employees e
  JOIN profiles p ON p.employee_id = e.id
  WHERE e.id = p_employee_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'EMPLOYEE_NOT_FOUND');
  END IF;

  -- ────────────────────────────────────────────
  -- 2. Validate ot_type
  -- ────────────────────────────────────────────
  IF p_ot_type NOT IN ('normal', 'holiday') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_OT_TYPE');
  END IF;

  -- ────────────────────────────────────────────
  -- 3. คำนวณชั่วโมง OT
  -- ────────────────────────────────────────────
  v_hours := ROUND(
    EXTRACT(EPOCH FROM (p_end_time - p_start_time)) / 3600.0,
    1
  );

  IF v_hours <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_TIME_RANGE');
  END IF;

  IF v_hours > 12 THEN
    RETURN jsonb_build_object('success', false, 'error', 'OT_HOURS_EXCEEDED_DAILY');
  END IF;

  -- ────────────────────────────────────────────
  -- 4. 72-hour window check
  -- ────────────────────────────────────────────
  v_is_backdate   := (p_ot_date < CURRENT_DATE);
  v_within_window := (
    CURRENT_DATE - p_ot_date <= 3  -- 72 ชม. = 3 วัน
  );

  IF v_is_backdate AND NOT v_within_window THEN
    RETURN jsonb_build_object(
      'success', false,
      'error',   'OT_WINDOW_EXCEEDED',
      'hint',    'ยื่น OT ย้อนหลังได้ไม่เกิน 72 ชั่วโมง (3 วัน)'
    );
  END IF;

  -- ────────────────────────────────────────────
  -- 5. Monthly max check (36 ชม./เดือน)
  -- ────────────────────────────────────────────
  SELECT COALESCE(SUM(hours), 0)
  INTO v_monthly_hours
  FROM ot_requests
  WHERE employee_id = p_employee_id
    AND status IN ('pending', 'approved')
    AND EXTRACT(YEAR  FROM ot_date) = EXTRACT(YEAR  FROM p_ot_date)
    AND EXTRACT(MONTH FROM ot_date) = EXTRACT(MONTH FROM p_ot_date);

  IF v_monthly_hours + v_hours > v_max_monthly_hours THEN
    RETURN jsonb_build_object(
      'success',          false,
      'error',            'MONTHLY_OT_EXCEEDED',
      'used_hours',       v_monthly_hours,
      'requested_hours',  v_hours,
      'max_hours',        v_max_monthly_hours,
      'hint',             'OT เกิน 36 ชม./เดือน — ต้องได้รับการยกเว้นจาก Owner'
    );
  END IF;

  -- ────────────────────────────────────────────
  -- 6. กำหนด rate
  -- เภสัชกร = fix 150 บาท/ชม. (D17)
  -- ปกติ = salary_base/30/8 * multiplier
  -- ────────────────────────────────────────────
  IF v_employee.role = 'pharmacist' OR
     v_employee.employment_type = 'pharmacist' THEN
    v_is_fixed_rate   := true;
    v_hourly_rate     := 150.00;
    v_rate_multiplier := 1.0;
  ELSIF p_ot_type = 'holiday' THEN
    v_is_fixed_rate   := false;
    v_hourly_rate     := NULL;
    v_rate_multiplier := 3.0;
  ELSE
    v_is_fixed_rate   := false;
    v_hourly_rate     := NULL;
    v_rate_multiplier := 1.5;
  END IF;

  -- ────────────────────────────────────────────
  -- 7. หา first approver (Supervisor หรือ Owner)
  -- ────────────────────────────────────────────
  IF v_employee.supervisor_id IS NOT NULL THEN
    SELECT p.id INTO v_first_approver_id
    FROM employees e
    JOIN profiles p ON p.employee_id = e.id
    WHERE e.id = v_employee.supervisor_id
    LIMIT 1;
  END IF;

  IF v_first_approver_id IS NULL THEN
    SELECT p.id INTO v_first_approver_id
    FROM profiles p
    WHERE p.role IN ('owner', 'owner_delegate')
      AND p.is_active = true
    ORDER BY p.role ASC
    LIMIT 1;
  END IF;

  -- ────────────────────────────────────────────
  -- 8. Insert ot_request
  -- ────────────────────────────────────────────
  INSERT INTO ot_requests (
    employee_id,
    ot_date,
    start_time,
    end_time,
    hours,
    ot_type,
    rate_multiplier,
    hourly_rate,
    is_fixed_rate,
    reason,
    evidence_url,
    status,
    approval_step,
    approval_step_max,
    current_approver_id,
    approver_chain,
    submitted_within_window,
    is_backdate
  )
  VALUES (
    p_employee_id,
    p_ot_date,
    p_start_time,
    p_end_time,
    v_hours,
    p_ot_type,
    v_rate_multiplier,
    v_hourly_rate,
    v_is_fixed_rate,
    p_reason,
    p_evidence_url,
    'pending',
    1,
    2,                      -- default Sup→Owner (2 steps)
    v_first_approver_id,
    '[]'::jsonb,
    v_within_window,
    v_is_backdate
  )
  RETURNING id INTO v_new_id;

  -- ────────────────────────────────────────────
  -- 9. Return
  -- ────────────────────────────────────────────
  RETURN jsonb_build_object(
    'success',          true,
    'ot_request_id',    v_new_id,
    'hours',            v_hours,
    'rate_multiplier',  v_rate_multiplier,
    'is_fixed_rate',    v_is_fixed_rate,
    'hourly_rate',      v_hourly_rate,
    'within_window',    v_within_window,
    'monthly_total',    v_monthly_hours + v_hours
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

GRANT EXECUTE ON FUNCTION submit_ot_request TO authenticated;