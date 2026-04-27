-- Function: submit_leave_request
-- หน้าที่: Staff ขอลา — validate ทุก business rule แล้ว insert
-- Security: SECURITY DEFINER (bypass RLS เพื่อ query ข้อมูลที่จำเป็น)
-- Date: 27 เม.ย. 2569

CREATE OR REPLACE FUNCTION submit_leave_request(
  p_employee_id     UUID,
  p_leave_type      TEXT,
  p_start_date      DATE,
  p_end_date        DATE,
  p_is_half_day     BOOLEAN DEFAULT false,
  p_half_day_period TEXT    DEFAULT NULL,
  p_reason          TEXT    DEFAULT NULL,
  p_attachment_url  TEXT    DEFAULT NULL,
  p_is_backdate     BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_employee          RECORD;
  v_days              DECIMAL(4,1);
  v_approval_step_max INTEGER;
  v_balance           RECORD;
  v_quota             DECIMAL(4,1);
  v_advance_days      INTEGER;
  v_advance_required  INTEGER;
  v_advance_met       BOOLEAN;
  v_is_probation      BOOLEAN;
  v_triggers_dili     BOOLEAN;
  v_new_id            UUID;
  v_current_year      INTEGER := EXTRACT(YEAR FROM CURRENT_DATE);
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
  -- 2. Validate leave_type
  -- ────────────────────────────────────────────
  IF p_leave_type NOT IN (
    'annual','sick','personal','maternity',
    'ordination','marriage','funeral','military','training'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_LEAVE_TYPE');
  END IF;

  -- ────────────────────────────────────────────
  -- 3. คำนวณจำนวนวัน
  -- ────────────────────────────────────────────
  IF p_is_half_day THEN
    v_days := 0.5;
  ELSE
    v_days := (p_end_date - p_start_date) + 1;
  END IF;

  IF v_days <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_DATE_RANGE');
  END IF;

  -- ────────────────────────────────────────────
  -- 4. Half-day validation
  -- ────────────────────────────────────────────
  IF p_is_half_day THEN
    -- ลาที่ไม่รองรับ half-day
    IF p_leave_type IN ('maternity','ordination','marriage','funeral','military','training') THEN
      RETURN jsonb_build_object('success', false, 'error', 'HALF_DAY_NOT_SUPPORTED');
    END IF;
    IF p_half_day_period NOT IN ('morning', 'afternoon') THEN
      RETURN jsonb_build_object('success', false, 'error', 'INVALID_HALF_DAY_PERIOD');
    END IF;
    -- half-day ต้อง start = end
    IF p_start_date != p_end_date THEN
      RETURN jsonb_build_object('success', false, 'error', 'HALF_DAY_MUST_BE_SINGLE_DAY');
    END IF;
  END IF;

  -- ────────────────────────────────────────────
  -- 5. Backdate validation (ลาป่วยเท่านั้น)
  -- ────────────────────────────────────────────
  IF p_is_backdate THEN
    IF p_leave_type != 'sick' THEN
      RETURN jsonb_build_object('success', false, 'error', 'BACKDATE_SICK_ONLY');
    END IF;
    -- window ≤ 3 วัน
    IF (CURRENT_DATE - p_start_date) > 3 THEN
      RETURN jsonb_build_object('success', false, 'error', 'BACKDATE_WINDOW_EXCEEDED');
    END IF;
    -- ต้องมี attachment ถ้า sick ≥ 3 วัน
    IF v_days >= 3 AND p_attachment_url IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'ATTACHMENT_REQUIRED');
    END IF;
  ELSE
    -- ลาปกติ: ห้าม start_date ในอดีต (ยกเว้น backdate)
    IF p_start_date < CURRENT_DATE THEN
      RETURN jsonb_build_object('success', false, 'error', 'PAST_DATE_NOT_ALLOWED');
    END IF;
  END IF;

  -- ────────────────────────────────────────────
  -- 6. Probation check
  -- ────────────────────────────────────────────
  -- ทดลองงาน = hire_date + 119 วัน
  v_is_probation := (
    v_employee.hire_date IS NOT NULL
    AND CURRENT_DATE < (v_employee.hire_date + INTERVAL '119 days')::DATE
  );

  IF v_is_probation AND p_leave_type = 'personal' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'PROBATION_NO_PERSONAL_LEAVE',
      'hint', 'ช่วงทดลองงาน ลากิจถือเป็น LWP — ติดต่อ HR Admin'
    );
  END IF;

  IF v_is_probation AND p_leave_type = 'annual' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'PROBATION_NO_ANNUAL_LEAVE',
      'hint', 'ลาพักร้อนได้หลังครบ 1 ปี — ติดต่อ HR Admin'
    );
  END IF;

  -- ────────────────────────────────────────────
  -- 7. Advance notice check
  -- ────────────────────────────────────────────
  v_advance_days := (p_start_date - CURRENT_DATE);

  CASE p_leave_type
    WHEN 'annual' THEN v_advance_required := 7;
    WHEN 'sick'   THEN v_advance_required := 0; -- ไม่ต้องแจ้งล่วงหน้า
    ELSE               v_advance_required := 3;
  END CASE;

  v_advance_met := (v_advance_days >= v_advance_required OR p_is_backdate);

  -- ไม่ block แต่ flag ไว้ → trigger ตัดเบี้ยขยัน (D16)

  -- ────────────────────────────────────────────
  -- 8. Quota check (ไม่ตรวจ military — ตามหมายเรียก)
  -- ────────────────────────────────────────────
  IF p_leave_type != 'military' THEN
    SELECT * INTO v_balance
    FROM leave_balances
    WHERE employee_id = p_employee_id
      AND year = v_current_year
      AND leave_type = p_leave_type;

    IF NOT FOUND THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'NO_LEAVE_BALANCE',
        'hint', 'ไม่พบ balance — ติดต่อ HR Admin'
      );
    END IF;

    IF v_balance.remaining_days < v_days THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'INSUFFICIENT_BALANCE',
        'remaining', v_balance.remaining_days,
        'requested', v_days
      );
    END IF;
  END IF;

  -- ────────────────────────────────────────────
  -- 9. คำนวณ approval_step_max
  -- ────────────────────────────────────────────
  IF v_days <= 3 THEN
    v_approval_step_max := 1;
  ELSIF v_days <= 7 THEN
    v_approval_step_max := 2;
  ELSE
    v_approval_step_max := 3;
  END IF;

  -- ────────────────────────────────────────────
  -- 10. Diligence trigger flag
  -- ────────────────────────────────────────────
  v_triggers_dili := (p_leave_type = 'sick');

  -- ────────────────────────────────────────────
  -- 11. Insert leave_request
  -- ────────────────────────────────────────────
  INSERT INTO leave_requests (
    employee_id,
    leave_type,
    start_date,
    end_date,
    days,
    is_half_day,
    half_day_period,
    reason,
    attachment_url,
    is_backdate,
    approval_step,
    approval_step_max,
    triggers_diligence_check,
    is_probation,
    advance_notice_met,
    status,
    approver_chain,
    current_approver_id
  )
  VALUES (
    p_employee_id,
    p_leave_type,
    p_start_date,
    p_end_date,
    v_days,
    p_is_half_day,
    p_half_day_period,
    p_reason,
    p_attachment_url,
    p_is_backdate,
    1,                    -- เริ่มที่ step 1 (Supervisor)
    v_approval_step_max,
    v_triggers_dili,
    v_is_probation,
    v_advance_met,
    'pending',
    '[]'::jsonb,          -- approver_chain เริ่มว่าง
    (                     -- current_approver = Supervisor ของพนักงาน
      SELECT p.id
      FROM employees e
      JOIN profiles p ON p.employee_id = e.id
      WHERE e.id = v_employee.supervisor_id
      LIMIT 1
    )
  )
  RETURNING id INTO v_new_id;

  -- ────────────────────────────────────────────
  -- 12. Return success
  -- ────────────────────────────────────────────
  RETURN jsonb_build_object(
    'success',            true,
    'leave_request_id',   v_new_id,
    'days',               v_days,
    'approval_step_max',  v_approval_step_max,
    'triggers_diligence', v_triggers_dili,
    'advance_notice_met', v_advance_met,
    'is_probation',       v_is_probation
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
GRANT EXECUTE ON FUNCTION submit_leave_request TO authenticated;