-- Function: submit_ot_request
-- หน้าที่: Staff ขอ OT — validate 72hr window, 36hr/week cap, auto-detect type, insert
-- Security: SECURITY DEFINER (bypass RLS)
-- Date: 29 เม.ย. 2569

CREATE OR REPLACE FUNCTION submit_ot_request(
  p_employee_id   UUID,
  p_work_date     DATE,
  p_start_time    TIME,
  p_end_time      TIME,
  p_reason        TEXT DEFAULT NULL,
  p_attachment_url TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_employee        RECORD;
  v_hours           DECIMAL(5,2);
  v_ot_type         TEXT;
  v_rate            DECIMAL(4,2);
  v_holiday         RECORD;
  v_week_start      DATE;
  v_week_ot_hours   DECIMAL(5,2);
  v_window_deadline TIMESTAMPTZ;
  v_supervisor_id   UUID;
  v_new_id          UUID;
BEGIN

  -- ────────────────────────────────────────────
  -- 1. ดึงข้อมูล employee
  -- ────────────────────────────────────────────
  SELECT e.id, e.role, e.supervisor_id, e.employment_type,
         p.hourly_rate, p.base_salary
  INTO v_employee
  FROM employees e
  LEFT JOIN payroll_details p
    ON p.employee_id = e.id
    AND p.payroll_run_id IS NULL  -- draft/current rate
  WHERE e.id = p_employee_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'EMPLOYEE_NOT_FOUND');
  END IF;

  -- PC ไม่มี OT
  IF v_employee.role = 'pc_staff' THEN
    RETURN jsonb_build_object('success', false, 'error', 'PC_NO_OT');
  END IF;

  -- ────────────────────────────────────────────
  -- 2. คำนวณชั่วโมง OT
  -- ────────────────────────────────────────────
  v_hours := EXTRACT(EPOCH FROM (p_end_time - p_start_time)) / 3600.0;

  IF v_hours <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_TIME_RANGE');
  END IF;

  IF v_hours > 12 THEN
    RETURN jsonb_build_object('success', false, 'error', 'OT_EXCEEDS_12HR_PER_DAY');
  END IF;

  -- ────────────────────────────────────────────
  -- 3. ตรวจ 72hr window (D12 — ขอได้ภายใน 72ชม.หลังทำงาน)
  -- ────────────────────────────────────────────
  v_window_deadline := (p_work_date::TIMESTAMPTZ + p_end_time) + INTERVAL '72 hours';

  IF NOW() > v_window_deadline THEN
    RETURN jsonb_build_object(
      'success', false,
      'error',   'OT_WINDOW_EXPIRED',
      'detail',  'เกิน 72 ชม.หลังทำงาน — ไม่สามารถขอย้อนหลังได้'
    );
  END IF;

  -- ────────────────────────────────────────────
  -- 4. ตรวจ 36hr/week cap
  -- ────────────────────────────────────────────
  v_week_start := date_trunc('week', p_work_date)::DATE;

  SELECT COALESCE(SUM(ot_hours), 0)
  INTO v_week_ot_hours
  FROM ot_requests
  WHERE employee_id = p_employee_id
    AND work_date >= v_week_start
    AND work_date < v_week_start + INTERVAL '7 days'
    AND status IN ('pending', 'approved');

  IF v_week_ot_hours + v_hours > 36 THEN
    RETURN jsonb_build_object(
      'success',          false,
      'error',            'OT_WEEKLY_CAP_EXCEEDED',
      'current_week_ot',  v_week_ot_hours,
      'requested_hours',  v_hours,
      'max_allowed',      36 - v_week_ot_hours,
      'detail',           'OT สัปดาห์นี้เต็ม 36 ชม.แล้ว'
    );
  END IF;

  -- ────────────────────────────────────────────
  -- 5. Auto-detect OT type + rate (D12)
  -- ────────────────────────────────────────────
  SELECT * INTO v_holiday
  FROM holiday_calendar
  WHERE date = p_work_date;

  IF v_holiday IS NULL THEN
    -- วันทำงานปกติ
    v_ot_type := 'weekday_ot';
    v_rate    := 1.5;

  ELSIF v_holiday.type = 'open_changed' THEN
    -- วันหยุดที่ย้ายมาทำงาน (ม.28)
    -- ช่วง shift = 2x, นอก shift = 3x
    v_ot_type := 'holiday_changed_ot';
    v_rate    := 3.0;

  ELSIF v_holiday.type = 'open_substitute' THEN
    -- วันหยุดที่ร้านเปิด (ได้ token แทน)
    v_ot_type := 'holiday_substitute_work';
    v_rate    := 1.0;  -- จ่ายปกติ + token แยก

  ELSE
    -- closed แต่มีคนมาทำงาน (edge case)
    v_ot_type := 'holiday_ot';
    v_rate    := 3.0;
  END IF;

  -- Pharmacist override (D17 — Fix 150/hr ไม่ว่า rate จะเป็นอะไร)
  -- จะ handle ตอน payroll calculation ไม่ใช่ตรงนี้
  -- เก็บ ot_type ไว้ให้ payroll engine รู้

  -- ────────────────────────────────────────────
  -- 6. ตรวจ duplicate
  -- ────────────────────────────────────────────
  IF EXISTS (
    SELECT 1 FROM ot_requests
    WHERE employee_id = p_employee_id
      AND work_date   = p_work_date
      AND status NOT IN ('rejected', 'cancelled')
      AND (
        (p_start_time, p_end_time) OVERLAPS (start_time, end_time)
      )
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'OT_DUPLICATE_OVERLAP');
  END IF;

  -- ────────────────────────────────────────────
  -- 7. ดึง supervisor
  -- ────────────────────────────────────────────
  SELECT auth_user_id INTO v_supervisor_id
  FROM employees e2
  JOIN profiles p2 ON p2.employee_id = e2.id
  WHERE e2.id = v_employee.supervisor_id;

  -- ────────────────────────────────────────────
  -- 8. Insert
  -- ────────────────────────────────────────────
  INSERT INTO ot_requests (
    employee_id,
    work_date,
    start_time,
    end_time,
    ot_hours,
    ot_type,
    rate_multiplier,
    reason,
    attachment_url,
    status,
    current_approver_id,
    approver_chain
  ) VALUES (
    p_employee_id,
    p_work_date,
    p_start_time,
    p_end_time,
    v_hours,
    v_ot_type,
    v_rate,
    p_reason,
    p_attachment_url,
    'pending',
    v_supervisor_id,
    '[]'::jsonb
  )
  RETURNING id INTO v_new_id;

  -- ────────────────────────────────────────────
  -- 9. Return
  -- ────────────────────────────────────────────
  RETURN jsonb_build_object(
    'success',          true,
    'ot_request_id',    v_new_id,
    'ot_type',          v_ot_type,
    'ot_hours',         v_hours,
    'rate_multiplier',  v_rate,
    'week_ot_total',    v_week_ot_hours + v_hours,
    'window_deadline',  v_window_deadline
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

GRANT EXECUTE ON FUNCTION submit_ot_request(UUID, DATE, TIME, TIME, TEXT, TEXT) TO authenticated;