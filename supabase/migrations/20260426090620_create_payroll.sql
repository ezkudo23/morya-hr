-- Payroll Runs
CREATE TABLE payroll_runs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  period_year INTEGER NOT NULL,
  period_month INTEGER NOT NULL CHECK (period_month BETWEEN 1 AND 12),
  round INTEGER NOT NULL CHECK (round IN (1, 2)),

  -- Status
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN (
    'draft',        -- กำลังคำนวณ
    'approved',     -- Owner approve แล้ว
    'transferred',  -- โอนเงินแล้ว
    'locked',       -- ล็อคแล้ว (ยื่น ปกส.)
    'closed'        -- ปิดรอบ
  )),

  -- Totals
  total_employees INTEGER NOT NULL DEFAULT 0,
  total_gross DECIMAL(12, 2) NOT NULL DEFAULT 0,
  total_net DECIMAL(12, 2) NOT NULL DEFAULT 0,
  total_sso_employee DECIMAL(12, 2) NOT NULL DEFAULT 0,
  total_sso_employer DECIMAL(12, 2) NOT NULL DEFAULT 0,
  total_wht DECIMAL(12, 2) NOT NULL DEFAULT 0,

  -- Approval
  approved_by UUID REFERENCES auth.users(id),
  approved_at TIMESTAMPTZ,
  transferred_at TIMESTAMPTZ,
  locked_at TIMESTAMPTZ,

  -- Emergency Unlock (D14)
  is_unlocked BOOLEAN NOT NULL DEFAULT false,
  unlock_approver_1 UUID REFERENCES auth.users(id),
  unlock_approver_2 UUID REFERENCES auth.users(id),
  unlock_reason TEXT,
  unlocked_at TIMESTAMPTZ,

  note TEXT,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE(period_year, period_month, round) -- ห้าม run ซ้ำ
);

-- Auto-update updated_at
CREATE TRIGGER payroll_runs_updated_at
  BEFORE UPDATE ON payroll_runs
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Index
CREATE INDEX payroll_runs_period_idx ON payroll_runs(period_year, period_month);
CREATE INDEX payroll_runs_status_idx ON payroll_runs(status);

-- RLS
ALTER TABLE payroll_runs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "payroll_runs_read_owner"
  ON payroll_runs FOR SELECT
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate')
  );

CREATE POLICY "payroll_runs_read_finance"
  ON payroll_runs FOR SELECT
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') = 'finance'
  );

CREATE POLICY "payroll_runs_insert_finance"
  ON payroll_runs FOR INSERT
  TO authenticated
  WITH CHECK (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate', 'finance')
  );

CREATE POLICY "payroll_runs_update_finance"
  ON payroll_runs FOR UPDATE
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate', 'finance')
  );

CREATE POLICY "payroll_runs_approve_owner"
  ON payroll_runs FOR UPDATE
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate')
  );

---

-- Payroll Details (รายละเอียดรายคน)
CREATE TABLE payroll_details (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  payroll_run_id UUID NOT NULL REFERENCES payroll_runs(id),
  employee_id UUID NOT NULL REFERENCES employees(id),

  -- Salary Base
  base_salary DECIMAL(10, 2) NOT NULL,
  worked_days DECIMAL(4, 1),   -- พนักงานใหม่/ลาออก
  absent_days DECIMAL(4, 1),   -- พนักงานเก่า LWP
  prorated_salary DECIMAL(10, 2) NOT NULL,

  -- Deductions
  lwp_days DECIMAL(4, 1) NOT NULL DEFAULT 0,
  lwp_deduction DECIMAL(10, 2) NOT NULL DEFAULT 0,

  -- Variable (Round 2)
  ot_amount DECIMAL(10, 2) NOT NULL DEFAULT 0,
  commission_amount DECIMAL(10, 2) NOT NULL DEFAULT 0,
  diligence_bonus DECIMAL(10, 2) NOT NULL DEFAULT 0,
  diligence_forfeited BOOLEAN NOT NULL DEFAULT false,
  other_income DECIMAL(10, 2) NOT NULL DEFAULT 0,

  -- Adjustments
  adjustment_amount DECIMAL(10, 2) NOT NULL DEFAULT 0,
  adjustment_note TEXT,

  -- Gross
  gross_income DECIMAL(10, 2) NOT NULL,

  -- SSO (D10)
  sso_base DECIMAL(10, 2) NOT NULL,
  sso_employee DECIMAL(10, 2) NOT NULL,
  sso_employer DECIMAL(10, 2) NOT NULL,

  -- WHT
  wht_amount DECIMAL(10, 2) NOT NULL DEFAULT 0,
  wht_ytd DECIMAL(12, 2) NOT NULL DEFAULT 0, -- YTD สำหรับคำนวณ bracket

  -- Net
  net_pay DECIMAL(10, 2) NOT NULL,

  -- Hybrid Logic Flag (D9)
  calculation_method TEXT NOT NULL CHECK (calculation_method IN (
    'days_worked',  -- พนักงานใหม่/ลาออก
    'days_absent'   -- พนักงานเก่า
  )),

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE(payroll_run_id, employee_id) -- 1 run 1 คน มีได้ 1 record
);

-- Index
CREATE INDEX payroll_details_run_idx ON payroll_details(payroll_run_id);
CREATE INDEX payroll_details_employee_idx ON payroll_details(employee_id);

-- RLS
ALTER TABLE payroll_details ENABLE ROW LEVEL SECURITY;

CREATE POLICY "payroll_details_read_admin"
  ON payroll_details FOR SELECT
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate', 'finance')
  );

-- Staff เห็นเฉพาะ payslip ตัวเอง
CREATE POLICY "payroll_details_read_self"
  ON payroll_details FOR SELECT
  TO authenticated
  USING (
    employee_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM payroll_runs
      WHERE id = payroll_run_id
      AND status IN ('transferred', 'locked', 'closed')
    )
  );

CREATE POLICY "payroll_details_write_finance"
  ON payroll_details FOR ALL
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate', 'finance')
  );

---

-- WHT Declarations (ลดหย่อนภาษี ลย.01)
CREATE TABLE wht_declarations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID NOT NULL REFERENCES employees(id),
  year INTEGER NOT NULL,

  -- ลดหย่อนส่วนตัว
  personal_allowance DECIMAL(10, 2) NOT NULL DEFAULT 60000,
  spouse_allowance DECIMAL(10, 2) NOT NULL DEFAULT 0,
  child_allowance DECIMAL(10, 2) NOT NULL DEFAULT 0,
  parent_allowance DECIMAL(10, 2) NOT NULL DEFAULT 0,

  -- ประกัน
  life_insurance DECIMAL(10, 2) NOT NULL DEFAULT 0,
  health_insurance DECIMAL(10, 2) NOT NULL DEFAULT 0,

  -- กองทุน
  rmf DECIMAL(10, 2) NOT NULL DEFAULT 0,
  ssf DECIMAL(10, 2) NOT NULL DEFAULT 0,

  -- รวม
  total_allowance DECIMAL(10, 2) GENERATED ALWAYS AS (
    personal_allowance + spouse_allowance + child_allowance +
    parent_allowance + life_insurance + health_insurance + rmf + ssf
  ) STORED,

  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(employee_id, year)
);

-- Auto-update updated_at
CREATE TRIGGER wht_declarations_updated_at
  BEFORE UPDATE ON wht_declarations
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- RLS
ALTER TABLE wht_declarations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "wht_declarations_read_admin"
  ON wht_declarations FOR SELECT
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate', 'finance', 'hr_admin')
  );

CREATE POLICY "wht_declarations_read_self"
  ON wht_declarations FOR SELECT
  TO authenticated
  USING (employee_id = auth.uid());

CREATE POLICY "wht_declarations_insert_self"
  ON wht_declarations FOR INSERT
  TO authenticated
  WITH CHECK (employee_id = auth.uid());

CREATE POLICY "wht_declarations_update_self"
  ON wht_declarations FOR UPDATE
  TO authenticated
  USING (employee_id = auth.uid());

CREATE POLICY "wht_declarations_write_admin"
  ON wht_declarations FOR ALL
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate', 'finance')
  );