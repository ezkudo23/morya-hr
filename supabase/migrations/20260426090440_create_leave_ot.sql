-- Leave Requests
CREATE TABLE leave_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID NOT NULL REFERENCES employees(id),

  -- ประเภทลา (9 ประเภท — D11)
  leave_type TEXT NOT NULL CHECK (leave_type IN (
    'annual',       -- พักร้อน 6 วัน/ปี
    'sick',         -- ป่วย 30 วัน/ปี
    'personal',     -- กิจ 3 วัน/ปี
    'maternity',    -- คลอด 45+45 วัน
    'ordination',   -- บวช 15 วัน
    'marriage',     -- สมรส 3 วัน
    'funeral',      -- ฌาปนกิจ 5 วัน
    'military',     -- ทหาร ม.35
    'training'      -- ฝึกอบรม ม.34 30 วัน/ปี
  )),

  -- วันที่
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  days DECIMAL(4, 1) NOT NULL, -- รองรับ 0.5 วัน
  is_half_day BOOLEAN NOT NULL DEFAULT false,
  half_day_period TEXT CHECK (half_day_period IN ('morning', 'afternoon')),

  -- รายละเอียด
  reason TEXT,
  attachment_url TEXT, -- ใบรับรองแพทย์ ฯลฯ

  -- Approval Chain
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN (
    'pending', 'approved', 'rejected', 'cancelled'
  )),
  approver_chain JSONB, -- [{role, user_id, approved_at}]
  current_approver_id UUID REFERENCES auth.users(id),
  approver_note TEXT,
  approved_at TIMESTAMPTZ,
  rejected_at TIMESTAMPTZ,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Auto-update updated_at
CREATE TRIGGER leave_requests_updated_at
  BEFORE UPDATE ON leave_requests
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Index
CREATE INDEX leave_requests_employee_idx ON leave_requests(employee_id);
CREATE INDEX leave_requests_status_idx ON leave_requests(status);
CREATE INDEX leave_requests_date_idx ON leave_requests(start_date, end_date);

-- RLS
ALTER TABLE leave_requests ENABLE ROW LEVEL SECURITY;

-- Owner/Delegate/HR Admin เห็นทั้งหมด
CREATE POLICY "leave_requests_read_admin"
  ON leave_requests FOR SELECT
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate', 'hr_admin')
  );

-- Supervisor เห็นเฉพาะทีม
CREATE POLICY "leave_requests_read_supervisor"
  ON leave_requests FOR SELECT
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') = 'supervisor'
    AND employee_id IN (
      SELECT id FROM employees WHERE supervisor_id = auth.uid()
    )
  );

-- Staff เห็นเฉพาะตัวเอง
CREATE POLICY "leave_requests_read_self"
  ON leave_requests FOR SELECT
  TO authenticated
  USING (employee_id = auth.uid());

-- Staff INSERT ได้เฉพาะของตัวเอง
CREATE POLICY "leave_requests_insert_self"
  ON leave_requests FOR INSERT
  TO authenticated
  WITH CHECK (employee_id = auth.uid());

-- Approver UPDATE ได้
CREATE POLICY "leave_requests_update_approver"
  ON leave_requests FOR UPDATE
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate', 'hr_admin', 'supervisor')
  );

---

-- Leave Balances (วันลาคงเหลือ)
CREATE TABLE leave_balances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID NOT NULL REFERENCES employees(id),
  year INTEGER NOT NULL,
  leave_type TEXT NOT NULL,
  entitled_days DECIMAL(4, 1) NOT NULL, -- วันลาที่มีสิทธิ์
  used_days DECIMAL(4, 1) NOT NULL DEFAULT 0,
  remaining_days DECIMAL(4, 1) GENERATED ALWAYS AS (entitled_days - used_days) STORED,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(employee_id, year, leave_type)
);

-- Auto-update updated_at
CREATE TRIGGER leave_balances_updated_at
  BEFORE UPDATE ON leave_balances
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- RLS
ALTER TABLE leave_balances ENABLE ROW LEVEL SECURITY;

CREATE POLICY "leave_balances_read_admin"
  ON leave_balances FOR SELECT
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate', 'hr_admin')
  );

CREATE POLICY "leave_balances_read_self"
  ON leave_balances FOR SELECT
  TO authenticated
  USING (employee_id = auth.uid());

CREATE POLICY "leave_balances_write_admin"
  ON leave_balances FOR ALL
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate', 'hr_admin')
  );

---

-- OT Requests
CREATE TABLE ot_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID NOT NULL REFERENCES employees(id),
  work_date DATE NOT NULL,
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  hours DECIMAL(4, 2) NOT NULL,

  -- ประเภท OT
  ot_type TEXT NOT NULL CHECK (ot_type IN (
    'weekday',          -- 1.5x
    'holiday_sub',      -- วันหยุด substitute 1.0x + token
    'holiday_changed',  -- วันหยุดเปลี่ยน 2.0x + consent
    'holiday_ot'        -- OT ในวันหยุดเปลี่ยน 3.0x
  )),
  rate_multiplier DECIMAL(3, 1) NOT NULL,

  -- Pharmacist Fix (D17)
  is_pharmacist_fixed BOOLEAN NOT NULL DEFAULT false,
  fixed_rate DECIMAL(10, 2), -- 150.00

  -- คำนวณ
  amount DECIMAL(10, 2),

  -- Consent (วันหยุดเปลี่ยน)
  requires_consent BOOLEAN NOT NULL DEFAULT false,
  consent_given BOOLEAN,
  consent_at TIMESTAMPTZ,

  -- Approval (D12: ≤72 ชม.)
  request_window_hours DECIMAL(5, 2),
  is_within_window BOOLEAN GENERATED ALWAYS AS (
    request_window_hours <= 72
  ) STORED,

  reason TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN (
    'pending', 'approved', 'rejected'
  )),
  approver_id UUID REFERENCES auth.users(id),
  approver_note TEXT,
  approved_at TIMESTAMPTZ,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Auto-update updated_at
CREATE TRIGGER ot_requests_updated_at
  BEFORE UPDATE ON ot_requests
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Index
CREATE INDEX ot_requests_employee_idx ON ot_requests(employee_id);
CREATE INDEX ot_requests_status_idx ON ot_requests(status);
CREATE INDEX ot_requests_date_idx ON ot_requests(work_date);

-- RLS
ALTER TABLE ot_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ot_requests_read_admin"
  ON ot_requests FOR SELECT
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate', 'hr_admin', 'finance')
  );

CREATE POLICY "ot_requests_read_supervisor"
  ON ot_requests FOR SELECT
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') = 'supervisor'
    AND employee_id IN (
      SELECT id FROM employees WHERE supervisor_id = auth.uid()
    )
  );

CREATE POLICY "ot_requests_read_self"
  ON ot_requests FOR SELECT
  TO authenticated
  USING (employee_id = auth.uid());

CREATE POLICY "ot_requests_insert_self"
  ON ot_requests FOR INSERT
  TO authenticated
  WITH CHECK (employee_id = auth.uid());

CREATE POLICY "ot_requests_update_approver"
  ON ot_requests FOR UPDATE
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate', 'hr_admin', 'supervisor')
  );

---

-- Substitute Tokens (วันหยุด token)
CREATE TABLE substitute_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID NOT NULL REFERENCES employees(id),
  ot_request_id UUID REFERENCES ot_requests(id),
  earned_date DATE NOT NULL,
  expires_at DATE NOT NULL, -- earned_date + 30 วัน
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN (
    'active', 'used', 'expired'
  )),
  used_date DATE,
  used_for_leave_id UUID REFERENCES leave_requests(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index
CREATE INDEX substitute_tokens_employee_idx ON substitute_tokens(employee_id);
CREATE INDEX substitute_tokens_status_idx ON substitute_tokens(status);
CREATE INDEX substitute_tokens_expires_idx ON substitute_tokens(expires_at);

-- RLS
ALTER TABLE substitute_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY "substitute_tokens_read_admin"
  ON substitute_tokens FOR SELECT
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate', 'hr_admin')
  );

CREATE POLICY "substitute_tokens_read_self"
  ON substitute_tokens FOR SELECT
  TO authenticated
  USING (employee_id = auth.uid());

CREATE POLICY "substitute_tokens_write_admin"
  ON substitute_tokens FOR ALL
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate', 'hr_admin')
  );