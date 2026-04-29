-- Function: get_payroll_summary
-- หน้าที่: ดึงสรุป payroll run สำหรับ Finance review ก่อน approve
-- Security: SECURITY DEFINER (bypass RLS)
-- Date: 29 เม.ย. 2569

CREATE OR REPLACE FUNCTION get_payroll_summary(
  p_payroll_run_id UUID,
  p_requester_id   UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_requester RECORD;
  v_run       RECORD;
  v_details   JSONB;
  v_summary   JSONB;
BEGIN

  -- ────────────────────────────────────────────
  -- 1. ตรวจสิทธิ์
  -- ────────────────────────────────────────────
  SELECT p.role INTO v_requester
  FROM profiles p
  WHERE p.id = p_requester_id;

  IF NOT FOUND OR v_requester.role NOT IN ('owner', 'owner_delegate', 'hr_admin', 'finance') THEN
    RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  -- ────────────────────────────────────────────
  -- 2. ดึง payroll_run
  -- ────────────────────────────────────────────
  SELECT * INTO v_run
  FROM payroll_runs
  WHERE id = p_payroll_run_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'PAYROLL_RUN_NOT_FOUND');
  END IF;

  -- ────────────────────────────────────────────
  -- 3. ดึง payroll_details รายคน
  -- ────────────────────────────────────────────
  SELECT jsonb_agg(
    jsonb_build_object(
      'employee_id',      pd.employee_id,
      'employee_code',    e.employee_code,
      'employee_name',    COALESCE(e.nickname, e.first_name),
      'cost_center',      cc.code,
      'mode',             pd.mode,
      'base_salary',      pd.base_salary,
      'days_worked',      pd.days_worked,
      'days_absent',      pd.days_absent,
      'leave_days',       pd.leave_days,
      'prorated_salary',  pd.prorated_salary,
      'ot_amount',        pd.ot_amount,
      'diligence',        pd.diligence,
      'sso_employee',     pd.sso_employee,
      'sso_employer',     pd.sso_employer,
      'wht',              pd.wht,
      'net_pay',          pd.net_pay,
      'bank_account',     e.bank_account,
      'bank_name',        e.bank_name
    )
    ORDER BY cc.code, e.employee_code
  )
  INTO v_details
  FROM payroll_details pd
  JOIN employees e  ON e.id  = pd.employee_id
  JOIN cost_centers cc ON cc.id = e.cost_center_id
  WHERE pd.payroll_run_id = p_payroll_run_id;

  -- ────────────────────────────────────────────
  -- 4. สรุปรายหมวด cost center
  -- ────────────────────────────────────────────
  SELECT jsonb_agg(
    jsonb_build_object(
      'cost_center',   cc.code,
      'employee_count', COUNT(pd.id),
      'total_net',     SUM(pd.net_pay),
      'total_sso',     SUM(pd.sso_employee),
      'total_wht',     SUM(pd.wht)
    )
    ORDER BY cc.code
  )
  INTO v_summary
  FROM payroll_details pd
  JOIN employees e    ON e.id  = pd.employee_id
  JOIN cost_centers cc ON cc.id = e.cost_center_id
  WHERE pd.payroll_run_id = p_payroll_run_id
  GROUP BY cc.code;

  -- ────────────────────────────────────────────
  -- 5. Return
  -- ────────────────────────────────────────────
  RETURN jsonb_build_object(
    'success',          true,
    'payroll_run_id',   v_run.id,
    'year',             v_run.year,
    'month',            v_run.month,
    'round',            v_run.round,
    'status',           v_run.status,
    'total_employees',  v_run.total_employees,
    'total_net_pay',    v_run.total_net_pay,
    'total_sso',        v_run.total_sso,
    'total_wht',        v_run.total_wht,
    'initiated_at',     v_run.initiated_at,
    'by_cost_center',   COALESCE(v_summary, '[]'::jsonb),
    'details',          COALESCE(v_details, '[]'::jsonb)
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

GRANT EXECUTE ON FUNCTION get_payroll_summary(UUID, UUID) TO authenticated;