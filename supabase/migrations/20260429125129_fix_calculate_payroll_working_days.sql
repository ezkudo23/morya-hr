-- Migration: fix_calculate_payroll_working_days
-- หน้าที่: แก้ working_days ให้นับถึง MIN(today, month_end) ไม่ใช่ 30 fixed
-- Date: 29 เม.ย. 2569

CREATE OR REPLACE FUNCTION calculate_payroll(
  p_employee_id   UUID,
  p_year          INTEGER,
  p_month         INTEGER,
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
  v_calc_end        DATE;  -- MIN(today, month_end)
  v_total_days      INTEGER; -- วันในเดือน (30 fixed สำหรับ prorated)
  v_working_days    INTEGER; -- วันทำงานจริงถึงวันนี้ (ไม่รวมหยุด)
  v_is_new_hire     BOOLEAN := false;
  v_is_resignation  BOOLEAN := false;
  v_same_month      BOOLEAN := false;
  v_resign_date     DATE;
  v_base_salary     DECIMAL(12,2);
  v_prorated_salary DECIMAL(12,2);
  v_ot_amount       DECIMAL(12,2) := 0;
  v_diligence       DECIMAL(12,2) := 0;
  v_sso_employee    DECIMAL(12,2) := 0;
  v_sso_employer    DECIMAL(12,2) := 0;
  v_sso_base        DECIMAL(12,2);
  v_wht             DECIMAL(12,2) := 0;
  v_net_pay         DECIMAL(12,2);
  v_days_worked     DECIMAL(5,2)  := 0;
  v_absent_days     DECIMAL(5,2)  := 0;
  v_leave_days      DECIMAL(5,2)  := 0;
  v_holiday_count   INTEGER := 0;
  v_checkin_count   INTEGER := 0;
  v_diligence_rec   RECORD;
  v_annual_income   DECIMAL(12,2);
  v_annual_deduct   DECIMAL(12,2);
  v_annual_tax      DECIMAL(12,2);
BEGIN

  SELECT e.id, e.role, e.employment_type, e.employment_status,
         e.hire_date, e.deleted_at, e.salary_base,
         e.cost_center_id, e.supervisor_id,
         e.is_attendance_exempt, e.is_sso_exempt
  INTO v_emp
  FROM employees e
  WHERE e.id = p_employee_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'EMPLOYEE_NOT_FOUND');
  END IF;

  IF v_emp.role = 'pc_staff' THEN
    RETURN jsonb_build_object('success', false, 'error', 'NO_PAYROLL_FOR_ROLE');
  END IF;

  v_base_salary := COALESCE(v_emp.salary_base, 0);
  v_month_start := DATE(p_year || '-' || LPAD(p_month::TEXT, 2, '0') || '-01');
  v_month_end   := (v_month_start + INTERVAL '1 month - 1 day')::DATE;
  v_calc_end    := LEAST(p_run_date, v_month_end);  -- ← KEY FIX
  v_total_days  := 30;  -- fixed 30 สำหรับ prorated calculation (D9)

  v_resign_date := CASE
    WHEN v_emp.employment_status = 'resigned' AND v_emp.deleted_at IS NOT NULL
    THEN v_emp.deleted_at::DATE
    ELSE NULL
  END;

  v_is_new_hire := (
    v_emp.hire_date >= v_month_start AND
    v_emp.hire_date <= v_month_end AND
    v_emp.hire_date != v_month_start
  );

  v_is_resignation := (
    v_resign_date IS NOT NULL AND
    v_resign_date >= v_month_start AND
    v_resign_date <= v_month_end AND
    v_resign_date <= p_run_date
  );

  v_same_month := v_is_new_hire AND v_is_resignation;

  -- นับวันหยุดนักขัตฤกษ์ถึง calc_end เท่านั้น
  SELECT COUNT(*) INTO v_holiday_count
  FROM holiday_calendar
  WHERE date >= v_month_start
    AND date <= v_calc_end
    AND type = 'closed';

  IF v_same_month THEN
    v_days_worked     := (v_resign_date - v_emp.hire_date + 1);
    v_prorated_salary := ROUND(v_base_salary * v_days_worked / v_total_days, 2);

  ELSIF v_is_new_hire THEN
    v_days_worked     := (v_calc_end - v_emp.hire_date + 1);
    v_prorated_salary := ROUND(v_base_salary * v_days_worked / v_total_days, 2);

  ELSIF v_is_resignation THEN
    v_days_worked     := (v_resign_date - v_month_start + 1);
    v_prorated_salary := ROUND(v_base_salary * v_days_worked / v_total_days, 2);

  ELSE
    IF v_emp.is_attendance_exempt THEN
      v_absent_days     := 0;
      v_prorated_salary := v_base_salary;
    ELSE
      -- วันทำงานที่ควรมาถึง calc_end (ไม่รวมหยุด)
      v_working_days := (v_calc_end - v_month_start + 1) - v_holiday_count;

      SELECT COALESCE(SUM(days), 0) INTO v_leave_days
      FROM leave_requests
      WHERE employee_id = p_employee_id
        AND status = 'approved'
        AND start_date >= v_month_start
        AND start_date <= v_calc_end;

      SELECT COUNT(DISTINCT event_date) INTO v_checkin_count
      FROM attendance_logs
      WHERE employee_id = p_employee_id
        AND event_type  = 'check_in'
        AND event_date  >= v_month_start
        AND event_date  <= v_calc_end;

      v_absent_days := GREATEST(v_working_days - v_checkin_count - v_leave_days, 0);

      v_prorated_salary := ROUND(v_base_salary * (v_total_days - v_absent_days) / v_total_days, 2);
    END IF;
  END IF;

  -- OT
  SELECT COALESCE(SUM(
    CASE
      WHEN v_emp.employment_type = 'pharmacist'
        THEN ot.hours * 150
      ELSE
        ROUND((v_base_salary / 30.0 / 8.0) * ot.rate_multiplier * ot.hours, 2)
    END
  ), 0)
  INTO v_ot_amount
  FROM ot_requests ot
  WHERE ot.employee_id = p_employee_id
    AND ot.status = 'approved'
    AND ot.ot_date >= v_month_start
    AND ot.ot_date <= v_calc_end;

  -- Diligence
  SELECT * INTO v_diligence_rec
  FROM employee_diligence_counters
  WHERE employee_id = p_employee_id
    AND year  = p_year
    AND month = p_month;

  v_diligence := CASE
    WHEN v_emp.is_attendance_exempt THEN 0
    WHEN v_diligence_rec IS NULL OR NOT v_diligence_rec.is_forfeited THEN 500
    ELSE 0
  END;

  -- SSO
  IF NOT COALESCE(v_emp.is_sso_exempt, false)
     AND (v_emp.employment_status != 'resigned' OR v_resign_date >= v_month_start)
  THEN
    v_sso_base     := GREATEST(1650, LEAST(v_prorated_salary, 15000));
    v_sso_employee := GREATEST(82.50, LEAST(ROUND(v_sso_base * 0.05, 2), 750));
    v_sso_employer := v_sso_employee;
  END IF;

  -- WHT
  v_annual_income := v_base_salary * 12;
  v_annual_deduct := LEAST(v_annual_income * 0.5, 100000) + 60000 + (v_sso_employee * 12);
  v_annual_income := GREATEST(v_annual_income - v_annual_deduct, 0);

  v_annual_tax := CASE
    WHEN v_annual_income <= 150000  THEN 0
    WHEN v_annual_income <= 300000  THEN (v_annual_income - 150000) * 0.05
    WHEN v_annual_income <= 500000  THEN 7500  + (v_annual_income - 300000) * 0.10
    WHEN v_annual_income <= 750000  THEN 27500 + (v_annual_income - 500000) * 0.15
    WHEN v_annual_income <= 1000000 THEN 65000 + (v_annual_income - 750000) * 0.20
    WHEN v_annual_income <= 2000000 THEN 115000 + (v_annual_income - 1000000) * 0.25
    WHEN v_annual_income <= 5000000 THEN 365000 + (v_annual_income - 2000000) * 0.30
    ELSE                                 1265000 + (v_annual_income - 5000000) * 0.35
  END;

  v_wht     := GREATEST(ROUND(v_annual_tax / 12, 2), 0);
  v_net_pay := v_prorated_salary + v_ot_amount + v_diligence - v_sso_employee - v_wht;

  RETURN jsonb_build_object(
    'success',          true,
    'employee_id',      p_employee_id,
    'year',             p_year,
    'month',            p_month,
    'mode',             CASE
                          WHEN v_same_month               THEN 'same_month'
                          WHEN v_is_new_hire              THEN 'new_hire'
                          WHEN v_is_resignation           THEN 'resignation'
                          WHEN v_emp.is_attendance_exempt THEN 'exempt'
                          ELSE 'normal'
                        END,
    'calc_end',         v_calc_end,
    'base_salary',      v_base_salary,
    'working_days',     v_working_days,
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
    'sso_exempt',       v_emp.is_sso_exempt,
    'wht',              v_wht,
    'net_pay',          v_net_pay
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', 'UNEXPECTED_ERROR', 'detail', SQLERRM);
END;
$$;