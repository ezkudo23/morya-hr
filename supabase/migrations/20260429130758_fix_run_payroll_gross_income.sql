-- Migration: fix_run_payroll_gross_income
-- หน้าที่: แก้ run_payroll — เพิ่ม gross_income ใน INSERT payroll_details
-- Date: 29 เม.ย. 2569

CREATE OR REPLACE FUNCTION run_payroll(
  p_year        INTEGER,
  p_month       INTEGER,
  p_round       INTEGER,
  p_initiated_by UUID
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
  v_total_gross   DECIMAL(14,2) := 0;
  v_total_sso     DECIMAL(14,2) := 0;
  v_total_wht     DECIMAL(14,2) := 0;
  v_initiator     RECORD;
  v_month_end     DATE;
  v_gross_income  DECIMAL(12,2);
  v_sso_base      DECIMAL(12,2);
BEGIN

  SELECT p.role INTO v_initiator
  FROM profiles p WHERE p.id = p_initiated_by;

  IF NOT FOUND OR v_initiator.role NOT IN ('owner', 'owner_delegate', 'hr_admin', 'finance') THEN
    RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  IF EXISTS (
    SELECT 1 FROM payroll_runs
    WHERE period_year  = p_year
      AND period_month = p_month
      AND round        = p_round
      AND status NOT IN ('closed')
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'PAYROLL_RUN_EXISTS');
  END IF;

  INSERT INTO payroll_runs (
    period_year, period_month, round, status, created_by
  ) VALUES (
    p_year, p_month, p_round, 'draft', p_initiated_by
  ) RETURNING id INTO v_run_id;

  v_month_end := (DATE(p_year || '-' || LPAD(p_month::TEXT,2,'0') || '-01') + INTERVAL '1 month - 1 day')::DATE;

  FOR v_emp IN
    SELECT e.id, e.employment_status, e.deleted_at, e.role
    FROM employees e
    WHERE e.role NOT IN ('pc_staff')
      AND (
        p_round = 1
        OR (
          p_round = 2 AND (
            e.employment_status != 'resigned' OR
            e.deleted_at::DATE > v_month_end
          )
        )
      )
  LOOP
    BEGIN
      v_calc := calculate_payroll(v_emp.id, p_year, p_month, CURRENT_DATE);

      IF (v_calc->>'success')::boolean THEN

        -- คำนวณ gross_income = prorated + ot + diligence
        v_gross_income := COALESCE((v_calc->>'prorated_salary')::DECIMAL, 0)
                        + COALESCE((v_calc->>'ot_amount')::DECIMAL, 0)
                        + COALESCE((v_calc->>'diligence')::DECIMAL, 0);

        -- คำนวณ sso_base
        v_sso_base := GREATEST(1650, LEAST(
          COALESCE((v_calc->>'prorated_salary')::DECIMAL, 0),
          15000
        ));

        INSERT INTO payroll_details (
          payroll_run_id,
          employee_id,
          calculation_method,
          base_salary,
          worked_days,
          absent_days,
          prorated_salary,
          ot_amount,
          diligence_bonus,
          diligence_forfeited,
          gross_income,
          sso_base,
          sso_employee,
          sso_employer,
          wht_amount,
          net_pay
        ) VALUES (
          v_run_id,
          v_emp.id,
          v_calc->>'mode',
          COALESCE((v_calc->>'base_salary')::DECIMAL, 0),
          (v_calc->>'days_worked')::DECIMAL,
          (v_calc->>'days_absent')::DECIMAL,
          COALESCE((v_calc->>'prorated_salary')::DECIMAL, 0),
          COALESCE((v_calc->>'ot_amount')::DECIMAL, 0),
          COALESCE((v_calc->>'diligence')::DECIMAL, 0),
          COALESCE((v_calc->>'diligence')::DECIMAL, 0) = 0,
          v_gross_income,
          v_sso_base,
          COALESCE((v_calc->>'sso_employee')::DECIMAL, 0),
          COALESCE((v_calc->>'sso_employer')::DECIMAL, 0),
          COALESCE((v_calc->>'wht')::DECIMAL, 0),
          COALESCE((v_calc->>'net_pay')::DECIMAL, 0)
        );

        v_total_gross := v_total_gross + v_gross_income;
        v_total_net   := v_total_net   + COALESCE((v_calc->>'net_pay')::DECIMAL, 0);
        v_total_sso   := v_total_sso   + COALESCE((v_calc->>'sso_employee')::DECIMAL, 0);
        v_total_wht   := v_total_wht   + COALESCE((v_calc->>'wht')::DECIMAL, 0);
        v_success_count := v_success_count + 1;

      ELSE
        v_errors := v_errors || jsonb_build_object(
          'employee_id', v_emp.id, 'error', v_calc->>'error'
        );
        v_error_count := v_error_count + 1;
      END IF;

    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors || jsonb_build_object(
        'employee_id', v_emp.id, 'error', SQLERRM
      );
      v_error_count := v_error_count + 1;
    END;
  END LOOP;

  UPDATE payroll_runs SET
    total_employees    = v_success_count,
    total_gross        = v_total_gross,
    total_net          = v_total_net,
    total_sso_employee = v_total_sso,
    total_wht          = v_total_wht,
    status             = CASE WHEN v_error_count = 0 THEN 'pending_approval' ELSE 'draft' END,
    updated_at         = NOW()
  WHERE id = v_run_id;

  RETURN jsonb_build_object(
    'success',        true,
    'payroll_run_id', v_run_id,
    'year',           p_year,
    'month',          p_month,
    'round',          p_round,
    'success_count',  v_success_count,
    'error_count',    v_error_count,
    'total_gross',    v_total_gross,
    'total_net_pay',  v_total_net,
    'total_sso',      v_total_sso,
    'total_wht',      v_total_wht,
    'errors',         v_errors
  );

EXCEPTION WHEN OTHERS THEN
  UPDATE payroll_runs SET status = 'cancelled' WHERE id = v_run_id;
  RETURN jsonb_build_object('success', false, 'error', 'FATAL_ERROR', 'detail', SQLERRM);
END;
$$;