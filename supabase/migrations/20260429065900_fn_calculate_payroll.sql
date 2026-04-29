-- Function: calculate_payroll
-- หน้าที่: คำนวณ payroll รายคน 1 เดือน — Days Worked/Absent, SSO, WHT, OT, Diligence
-- Security: SECURITY DEFINER (bypass RLS)
-- Date: 29 เม.ย. 2569

CREATE OR REPLACE FUNCTION calculate_payroll(
  p_employee_id   UUID,
  p_year          INTEGER,
  p_month         INTEGER,  -- 1-12
  p_run_date      DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_emp             RECORD;
  v_month_start     DATE;
  v_month_end       DATE;
  v_working_days    INTEGER;  -- วันทำงานในเดือน (ไม่รวมวันหยุด)
  v_days_worked     DECIMAL(5,2);
  v_days_absent     DECIMAL(5,2);
  v_is_new_hire     BOOLEAN := false;
  v_is_resignation  BOOLEAN := false;
  v_same_month      BOOLEAN := false;

  -- Salary components
  v_base_salary     DECIMAL(12,2);
  v_prorated_salary DECIMAL(12,2);
  v_ot_amount       DECIMAL(12,2) := 0;
  v_diligence       DECIMAL(12,2) := 0;
  v_sso_employee    DECIMAL(12,2) := 0;
  v_sso_employer    DECIMAL(12,2) := 0;
  v_wht             DECIMAL(12,2) := 0;
  v_net_pay         DECIMAL(12,2);

  -- Counters
  v_holiday_count   INTEGER := 0;
  v_leave_days      DECIMAL(5,2) := 0;
  v_absent_days     DECIMAL(5,2) := 0;
  v_diligence_rec   RECORD;
BEGIN

  -- ────────────────────────────────────────────
  -- 1. ดึงข้อมูล employee
  -- ────────────────────────────────────────────
  SELECT
    e.id, e.role, e.hire_date, e.resignation_date,
    e.base_salary, e.diligence_allowance,
    e.supervisor_id, e.cost_center_id,
    e.is_sso_exempt
  INTO v_emp
  FROM employees e
  WHERE e.id = p_employee_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'EMPLOYEE_NOT_FOUND');
  END IF;

  -- PC และ SSO-only ไม่มี payroll
  IF v_emp.role IN ('pc_staff', 'sso_only') THEN
    RETURN jsonb_build_object('success', false, 'error', 'NO_PAYROLL_FOR_ROLE');
  END IF;

  v_base_salary := v_emp.base_salary;

  -- ────────────────────────────────────────────
  -- 2. กำหนดช่วงเดือน
  -- ────────────────────────────────────────────
  v_month_start := DATE(p_year || '-' || LPAD(p_month::TEXT, 2, '0') || '-01');
  v_month_end   := (v_month_start + INTERVAL '1 month - 1 day')::DATE;

  -- ────────────────────────────────────────────
  -- 3. ตรวจ Days Worked vs Days Absent mode
  -- ────────────────────────────────────────────
  v_is_new_hire := (
    v_emp.hire_date >= v_month_start AND
    v_emp.hire_date <= v_month_end AND
    v_emp.hire_date != v_month_start  -- ไม่ใช่วันที่ 1
  );

  v_is_resignation := (
    v_emp.resignation_date IS NOT NULL AND
    v_emp.resignation_date >= v_month_start AND
    v_emp.resignation_date <= v_month_end AND
    v_emp.resignation_date <= p_run_date
  );

  v_same_month := v_is_new_hire AND v_is_resignation;

  -- ────────────────────────────────────────────
  -- 4. นับวันหยุดนักขัตฤกษ์ในเดือน
  -- ────────────────────────────────────────────
  SELECT COUNT(*) INTO v_holiday_count
  FROM holiday_calendar
  WHERE date >= v_month_start
    AND date <= v_month_end
    AND type = 'closed';

  -- ────────────────────────────────────────────
  -- 5. คำนวณ days
  -- ────────────────────────────────────────────

  IF v_same_month THEN
    -- เริ่มและลาออกเดือนเดียวกัน
    v_days_worked := (v_emp.resignation_date - v_emp.hire_date + 1);
    v_prorated_salary := ROUND(v_base_salary * v_days_worked / 30, 2);

  ELSIF v_is_new_hire THEN
    -- เริ่มงานกลางเดือน — นับจาก hire_date ถึงสิ้นเดือน
    v_days_worked := (v_month_end - v_emp.hire_date + 1);
    v_prorated_salary := ROUND(v_base_salary * v_days_worked / 30, 2);

  ELSIF v_is_resignation THEN
    -- ลาออกกลางเดือน — นับจากต้นเดือนถึง resign_date
    v_days_worked := (v_emp.resignation_date - v_month_start + 1);
    v_prorated_salary := ROUND(v_base_salary * v_days_worked / 30, 2);

  ELSE
    -- พนักงานเก่า — Days Absent mode
    -- นับวันลาที่ approved (ไม่หัก)
    SELECT COALESCE(SUM(days), 0) INTO v_leave_days
    FROM leave_requests
    WHERE employee_id = p_employee_id
      AND status = 'approved'
      AND EXTRACT(YEAR FROM start_date)  = p_year
      AND EXTRACT(MONTH FROM start_date) = p_month;

    -- นับวันขาดจริงจาก attendance (ไม่มี log + ไม่มี leave)
    SELECT COALESCE(
      -- วันทำงานที่ควรมา - วันที่มีจริง - วันลา approved
      (30 - v_holiday_count) -
      (SELECT COUNT(DISTINCT DATE(check_in)) FROM attendance_logs
       WHERE employee_id = p_employee_id
         AND EXTRACT(YEAR FROM check_in)  = p_year
         AND EXTRACT(MONTH FROM check_in) = p_month) -
      v_leave_days,
      0
    ) INTO v_absent_days;

    v_absent_days     := GREATEST(v_absent_days, 0);
    v_prorated_salary := ROUND(v_base_salary * (30 - v_absent_days) / 30, 2);
  END IF;

  -- ────────────────────────────────────────────
  -- 6. OT Amount (approved OT เดือนนี้)
  -- ────────────────────────────────────────────
  SELECT COALESCE(SUM(
    CASE
      -- Pharmacist fix 150/hr (D17)
      WHEN v_emp.role = 'pharmacist'
        THEN ot.ot_hours * 150
      ELSE
        -- คำนวณจาก hourly rate × multiplier
        -- hourly rate = base_salary / 30 / 8
        ROUND((v_base_salary / 30 / 8) * ot.rate_multiplier * ot.ot_hours, 2)
    END
  ), 0)
  INTO v_ot_amount
  FROM ot_requests ot
  WHERE ot.employee_id = p_employee_id
    AND ot.status = 'approved'
    AND EXTRACT(YEAR FROM ot.work_date)  = p_year
    AND EXTRACT(MONTH FROM ot.work_date) = p_month;

  -- ────────────────────────────────────────────
  -- 7. Diligence Allowance (D16 + C-03 + C-04)
  -- ────────────────────────────────────────────
  SELECT * INTO v_diligence_rec
  FROM employee_diligence_counters
  WHERE employee_id = p_employee_id
    AND year  = p_year
    AND month = p_month;

  IF v_diligence_rec IS NULL OR NOT v_diligence_rec.is_forfeited THEN
    v_diligence := COALESCE(v_emp.diligence_allowance, 0);
  ELSE
    v_diligence := 0;
  END IF;

  -- ────────────────────────────────────────────
  -- 8. SSO (D10)
  -- max(1650, min(salary, 15000)) × 5% floor 82.50 cap 750
  -- ────────────────────────────────────────────
  IF NOT COALESCE(v_emp.is_sso_exempt, false) THEN
    DECLARE
      v_sso_base DECIMAL(12,2);
    BEGIN
      v_sso_base     := GREATEST(1650, LEAST(v_prorated_salary, 15000));
      v_sso_employee := GREATEST(82.50, LEAST(ROUND(v_sso_base * 0.05, 2), 750));
      v_sso_employer := v_sso_employee;  -- employer match
    END;
  END IF;

  -- ────────────────────────────────────────────
  -- 9. WHT — annualize จาก full salary (ไม่ใช่ prorated)
  -- ────────────────────────────────────────────
  DECLARE
    v_annual_income   DECIMAL(12,2);
    v_annual_deduct   DECIMAL(12,2);
    v_annual_tax      DECIMAL(12,2);
    v_monthly_tax     DECIMAL(12,2);
  BEGIN
    -- Annualize จาก full base salary (ไม่ prorated)
    v_annual_income := v_base_salary * 12;

    -- Standard deduction 50% ไม่เกิน 100,000
    v_annual_deduct := LEAST(v_annual_income * 0.5, 100000);

    -- Personal allowance 60,000
    v_annual_deduct := v_annual_deduct + 60000;

    -- SSO deduction (annual)
    v_annual_deduct := v_annual_deduct + (v_sso_employee * 12);

    v_annual_income := GREATEST(v_annual_income - v_annual_deduct, 0);

    -- Progressive tax (ปี 2567)
    v_annual_tax := CASE
      WHEN v_annual_income <= 150000    THEN 0
      WHEN v_annual_income <= 300000    THEN (v_annual_income - 150000) * 0.05
      WHEN v_annual_income <= 500000    THEN 7500  + (v_annual_income - 300000) * 0.10
      WHEN v_annual_income <= 750000    THEN 27500 + (v_annual_income - 500000) * 0.15
      WHEN v_annual_income <= 1000000   THEN 65000 + (v_annual_income - 750000) * 0.20
      WHEN v_annual_income <= 2000000   THEN 115000 + (v_annual_income - 1000000) * 0.25
      WHEN v_annual_income <= 5000000   THEN 365000 + (v_annual_income - 2000000) * 0.30
      ELSE                                   1265000 + (v_annual_income - 5000000) * 0.35
    END;

    v_wht := GREATEST(ROUND(v_annual_tax / 12, 2), 0);
  END;

  -- ────────────────────────────────────────────
  -- 10. Net Pay
  -- ────────────────────────────────────────────
  v_net_pay := v_prorated_salary + v_ot_amount + v_diligence
               - v_sso_employee - v_wht;

  -- ────────────────────────────────────────────
  -- 11. Return
  -- ────────────────────────────────────────────
  RETURN jsonb_build_object(
    'success',          true,
    'employee_id',      p_employee_id,
    'year',             p_year,
    'month',            p_month,
    'mode',             CASE
                          WHEN v_same_month     THEN 'same_month'
                          WHEN v_is_new_hire    THEN 'new_hire'
                          WHEN v_is_resignation THEN 'resignation'
                          ELSE 'normal'
                        END,
    'base_salary',      v_base_salary,
    'days_worked',      CASE WHEN v_is_new_hire OR v_is_resignation OR v_same_month
                             THEN v_days_worked ELSE NULL END,
    'days_absent',      CASE WHEN NOT (v_is_new_hire OR v_is_resignation OR v_same_month)
                             THEN v_absent_days ELSE NULL END,
    'leave_days',       v_leave_days,
    'prorated_salary',  v_prorated_salary,
    'ot_amount',        v_ot_amount,
    'diligence',        v_diligence,
    'sso_employee',     v_sso_employee,
    'sso_employer',     v_sso_employer,
    'wht',              v_wht,
    'net_pay',          v_net_pay
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

GRANT EXECUTE ON FUNCTION calculate_payroll(UUID, INTEGER, INTEGER, DATE) TO authenticated;