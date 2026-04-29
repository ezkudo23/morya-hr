-- Function: run_payroll
-- หน้าที่: สร้าง payroll run + คำนวณทุกคน + insert payroll_details
-- Security: SECURITY DEFINER (bypass RLS)
-- Date: 29 เม.ย. 2569

CREATE OR REPLACE FUNCTION run_payroll(
  p_year        INTEGER,
  p_month       INTEGER,
  p_round       INTEGER,  -- 1 = เงินเดือน, 2 = commission
  p_initiated_by UUID     -- auth.users.id ของ Finance/Owner ที่สั่ง run
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_run_id        UUID;
  v_emp           RECORD;
  v_calc          JSONB;
  v_success_count INTEGER := 0;
  v_error_count   INTEGER := 0;
  v_errors        JSONB   := '[]'::jsonb;
  v_total_net     DECIMAL(14,2) := 0;
  v_total_sso     DECIMAL(14,2) := 0;
  v_total_wht     DECIMAL(14,2) := 0;
  v_initiator     RECORD;
BEGIN

  -- ────────────────────────────────────────────
  -- 1. ตรวจสิทธิ์
  -- ────────────────────────────────────────────
  SELECT p.role INTO v_initiator
  FROM profiles p
  WHERE p.id = p_initiated_by;

  IF NOT FOUND OR v_initiator.role NOT IN ('owner', 'owner_delegate', 'hr_admin', 'finance') THEN
    RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  -- ────────────────────────────────────────────
  -- 2. ตรวจ duplicate run
  -- ────────────────────────────────────────────
  IF EXISTS (
    SELECT 1 FROM payroll_runs
    WHERE year  = p_year
      AND month = p_month
      AND round = p_round
      AND status NOT IN ('cancelled')
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error',   'PAYROLL_RUN_EXISTS',
      'detail',  'Payroll รอบนี้มีอยู่แล้ว — cancel ก่อนถึงจะ run ใหม่ได้'
    );
  END IF;

  -- ────────────────────────────────────────────
  -- 3. สร้าง payroll_run record
  -- ────────────────────────────────────────────
  INSERT INTO payroll_runs (
    year, month, round, status, initiated_by, initiated_at
  ) VALUES (
    p_year, p_month, p_round, 'draft', p_initiated_by, NOW()
  )
  RETURNING id INTO v_run_id;

  -- ────────────────────────────────────────────
  -- 4. Loop ทุก employee ที่ต้อง run payroll
  -- ────────────────────────────────────────────
  FOR v_emp IN
    SELECT e.id, e.role, e.resignation_date
    FROM employees e
    WHERE e.role NOT IN ('pc_staff', 'sso_only')
      -- Round 2: ไม่รวมคนที่ลาออกกลางเดือน (D: ลาออก = ไม่ได้ commission)
      AND (
        p_round = 1
        OR (
          p_round = 2 AND (
            e.resignation_date IS NULL OR
            e.resignation_date > (DATE(p_year || '-' || LPAD(p_month::TEXT,2,'0') || '-01') + INTERVAL '1 month - 1 day')::DATE
          )
        )
      )
  LOOP
    BEGIN
      -- เรียก calculate_payroll
      v_calc := calculate_payroll(v_emp.id, p_year, p_month, CURRENT_DATE);

      IF (v_calc->>'success')::boolean THEN
        -- Insert payroll_details
        INSERT INTO payroll_details (
          payroll_run_id,
          employee_id,
          mode,
          base_salary,
          days_worked,
          days_absent,
          leave_days,
          prorated_salary,
          ot_amount,
          diligence,
          sso_employee,
          sso_employer,
          wht,
          net_pay
        ) VALUES (
          v_run_id,
          v_emp.id,
          v_calc->>'mode',
          (v_calc->>'base_salary')::DECIMAL,
          (v_calc->>'days_worked')::DECIMAL,
          (v_calc->>'days_absent')::DECIMAL,
          (v_calc->>'leave_days')::DECIMAL,
          (v_calc->>'prorated_salary')::DECIMAL,
          (v_calc->>'ot_amount')::DECIMAL,
          (v_calc->>'diligence')::DECIMAL,
          (v_calc->>'sso_employee')::DECIMAL,
          (v_calc->>'sso_employer')::DECIMAL,
          (v_calc->>'wht')::DECIMAL,
          (v_calc->>'net_pay')::DECIMAL
        );

        v_total_net := v_total_net + (v_calc->>'net_pay')::DECIMAL;
        v_total_sso := v_total_sso + (v_calc->>'sso_employee')::DECIMAL;
        v_total_wht := v_total_wht + (v_calc->>'wht')::DECIMAL;
        v_success_count := v_success_count + 1;

      ELSE
        -- บันทึก error แต่ไม่หยุด loop
        v_errors := v_errors || jsonb_build_object(
          'employee_id', v_emp.id,
          'error',       v_calc->>'error'
        );
        v_error_count := v_error_count + 1;
      END IF;

    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors || jsonb_build_object(
        'employee_id', v_emp.id,
        'error',       SQLERRM
      );
      v_error_count := v_error_count + 1;
    END;
  END LOOP;

  -- ────────────────────────────────────────────
  -- 5. Update payroll_run summary
  -- ────────────────────────────────────────────
  UPDATE payroll_runs SET
    total_employees = v_success_count,
    total_net_pay   = v_total_net,
    total_sso       = v_total_sso,
    total_wht       = v_total_wht,
    status          = CASE WHEN v_error_count = 0 THEN 'pending_approval' ELSE 'draft' END,
    updated_at      = NOW()
  WHERE id = v_run_id;

  -- ────────────────────────────────────────────
  -- 6. Return
  -- ────────────────────────────────────────────
  RETURN jsonb_build_object(
    'success',       true,
    'payroll_run_id', v_run_id,
    'year',          p_year,
    'month',         p_month,
    'round',         p_round,
    'success_count', v_success_count,
    'error_count',   v_error_count,
    'total_net_pay', v_total_net,
    'total_sso',     v_total_sso,
    'total_wht',     v_total_wht,
    'errors',        v_errors
  );

EXCEPTION
  WHEN OTHERS THEN
    -- Rollback run record ถ้า fatal error
    UPDATE payroll_runs SET status = 'cancelled' WHERE id = v_run_id;
    RETURN jsonb_build_object(
      'success', false,
      'error',   'FATAL_ERROR',
      'detail',  SQLERRM
    );
END;
$$;

GRANT EXECUTE ON FUNCTION run_payroll(INTEGER, INTEGER, INTEGER, UUID) TO authenticated;