-- Employees
CREATE TABLE employees (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_code TEXT UNIQUE, -- MY01-26, PC01-03, CEO02
  full_name_th TEXT NOT NULL,
  full_name_en TEXT,
  nickname TEXT,

  -- Role & Status
  role TEXT NOT NULL CHECK (role IN (
    'owner', 'owner_delegate', 'hr_admin', 'finance',
    'it_support', 'supervisor', 'staff', 'pc_staff'
  )),
  employment_type TEXT NOT NULL CHECK (employment_type IN (
    'regular_salary', 'director_salary'
  )),
  employment_status TEXT NOT NULL DEFAULT 'active' CHECK (employment_status IN (
    'active', 'active_no_payroll', 'probation',
    'on_leave', 'resigned', 'terminated'
  )),

  -- Organization
  cost_center_id UUID NOT NULL REFERENCES cost_centers(id),
  supervisor_id UUID REFERENCES employees(id), -- self-reference

  -- Compensation
  salary_base DECIMAL(10, 2) NOT NULL DEFAULT 0,
  hire_date DATE NOT NULL,
  probation_end_date DATE, -- hire_date + 119 วัน

  -- Personal Info
  tax_id TEXT,
  sso_id TEXT,
  date_of_birth DATE,
  phone TEXT,
  bank_account TEXT,
  bank_name TEXT,

  -- LINE
  line_user_id TEXT UNIQUE,

  -- Pharmacist
  pharmacist_license TEXT,
  pharmacist_license_expiry DATE,

  -- PC Sponsor
  pc_sponsor TEXT, -- NBD, Blackmores, Wellgate

  -- Soft Delete
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ
);

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER employees_updated_at
  BEFORE UPDATE ON employees
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- RLS
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;

-- Owner/Delegate/HR Admin เห็นทั้งหมด
CREATE POLICY "employees_read_admin"
  ON employees FOR SELECT
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate', 'hr_admin')
    AND deleted_at IS NULL
  );

-- Supervisor เห็นเฉพาะทีมตัวเอง
CREATE POLICY "employees_read_supervisor"
  ON employees FOR SELECT
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') = 'supervisor'
    AND supervisor_id = auth.uid()
    AND deleted_at IS NULL
  );

-- Staff/PC เห็นเฉพาะตัวเอง
CREATE POLICY "employees_read_self"
  ON employees FOR SELECT
  TO authenticated
  USING (
    id = auth.uid()
    AND deleted_at IS NULL
  );

-- Finance เห็นเฉพาะ fields ที่จำเป็น (ผ่าน view แยกทีหลัง)
-- Owner/Delegate/HR Admin แก้ได้
CREATE POLICY "employees_write_admin"
  ON employees FOR ALL
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate', 'hr_admin')
  );