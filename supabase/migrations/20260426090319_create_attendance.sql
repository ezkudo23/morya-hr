-- Attendance Logs
CREATE TABLE attendance_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID NOT NULL REFERENCES employees(id),
  event_type TEXT NOT NULL CHECK (event_type IN ('check_in', 'check_out')),
  event_date DATE NOT NULL,
  timestamp_reported TIMESTAMPTZ NOT NULL,
  timestamp_accepted TIMESTAMPTZ NOT NULL,

  -- GPS
  gps_latitude DECIMAL(10, 7),
  gps_longitude DECIMAL(10, 7),

  -- Location
  home_cost_center_id UUID NOT NULL REFERENCES cost_centers(id),
  actual_cost_center_id UUID NOT NULL REFERENCES cost_centers(id),
  is_cross_location BOOLEAN GENERATED ALWAYS AS (
    home_cost_center_id != actual_cost_center_id
  ) STORED,

  -- Shift
  shift_id UUID REFERENCES shifts(id),

  -- Late
  is_late BOOLEAN NOT NULL DEFAULT false,
  late_minutes INTEGER NOT NULL DEFAULT 0,

  -- Correction
  is_corrected BOOLEAN NOT NULL DEFAULT false,
  correction_request_id UUID, -- FK เพิ่มทีหลัง

  -- Offline
  auto_closed BOOLEAN NOT NULL DEFAULT false,
  is_offline BOOLEAN NOT NULL DEFAULT false,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index
CREATE INDEX attendance_logs_employee_date_idx ON attendance_logs(employee_id, event_date);
CREATE INDEX attendance_logs_date_idx ON attendance_logs(event_date);
CREATE INDEX attendance_logs_cross_location_idx ON attendance_logs(is_cross_location) WHERE is_cross_location = true;

-- RLS
ALTER TABLE attendance_logs ENABLE ROW LEVEL SECURITY;

-- Owner/Delegate/HR Admin เห็นทั้งหมด
CREATE POLICY "attendance_logs_read_admin"
  ON attendance_logs FOR SELECT
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate', 'hr_admin')
  );

-- Supervisor เห็นเฉพาะทีม
CREATE POLICY "attendance_logs_read_supervisor"
  ON attendance_logs FOR SELECT
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') = 'supervisor'
    AND employee_id IN (
      SELECT id FROM employees WHERE supervisor_id = auth.uid()
    )
  );

-- Staff/PC เห็นเฉพาะตัวเอง
CREATE POLICY "attendance_logs_read_self"
  ON attendance_logs FOR SELECT
  TO authenticated
  USING (employee_id = auth.uid());

-- INSERT ได้ทุก authenticated (check-in/out)
CREATE POLICY "attendance_logs_insert"
  ON attendance_logs FOR INSERT
  TO authenticated
  WITH CHECK (employee_id = auth.uid());

-- แก้ได้เฉพาะ admin (correction)
CREATE POLICY "attendance_logs_update_admin"
  ON attendance_logs FOR UPDATE
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate', 'hr_admin')
  );

---

-- Correction Requests
CREATE TABLE correction_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID NOT NULL REFERENCES employees(id),
  attendance_log_id UUID REFERENCES attendance_logs(id),
  event_date DATE NOT NULL,

  -- ประเภท correction
  correction_type TEXT NOT NULL CHECK (correction_type IN (
    'forgot_checkin',   -- ลืม check-in
    'forgot_checkout',  -- ลืม check-out
    'wrong_time',       -- เวลาผิด
    'wrong_location'    -- location ผิด
  )),

  -- ข้อมูลที่ขอแก้
  claimed_time TIMESTAMPTZ NOT NULL,
  reason TEXT NOT NULL,
  evidence_url TEXT,

  -- Window (ตาม D12: 72 ชม.)
  window_type TEXT NOT NULL CHECK (window_type IN (
    'self',    -- ≤24 ชม. — self correct ใน LIFF
    'flow',    -- 24-72 ชม. — Supervisor approve
    'manual'   -- >72 ชม. — HR + Owner
  )),
  hours_since_event DECIMAL(5, 2),

  -- Approval
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN (
    'pending', 'approved', 'rejected'
  )),
  approver_id UUID REFERENCES auth.users(id),
  approver_note TEXT,
  approved_at TIMESTAMPTZ,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- FK กลับไป attendance_logs
ALTER TABLE attendance_logs
  ADD CONSTRAINT attendance_logs_correction_fk
  FOREIGN KEY (correction_request_id)
  REFERENCES correction_requests(id);

-- Auto-update updated_at
CREATE TRIGGER correction_requests_updated_at
  BEFORE UPDATE ON correction_requests
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Index
CREATE INDEX correction_requests_employee_idx ON correction_requests(employee_id);
CREATE INDEX correction_requests_status_idx ON correction_requests(status);
CREATE INDEX correction_requests_date_idx ON correction_requests(event_date);

-- RLS
ALTER TABLE correction_requests ENABLE ROW LEVEL SECURITY;

-- Owner/Delegate/HR Admin เห็นทั้งหมด
CREATE POLICY "correction_requests_read_admin"
  ON correction_requests FOR SELECT
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate', 'hr_admin')
  );

-- Supervisor เห็นเฉพาะทีม
CREATE POLICY "correction_requests_read_supervisor"
  ON correction_requests FOR SELECT
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') = 'supervisor'
    AND employee_id IN (
      SELECT id FROM employees WHERE supervisor_id = auth.uid()
    )
  );

-- Staff เห็นเฉพาะตัวเอง
CREATE POLICY "correction_requests_read_self"
  ON correction_requests FOR SELECT
  TO authenticated
  USING (employee_id = auth.uid());

-- Staff INSERT ได้เฉพาะของตัวเอง
CREATE POLICY "correction_requests_insert_self"
  ON correction_requests FOR INSERT
  TO authenticated
  WITH CHECK (employee_id = auth.uid());

-- Supervisor/Admin UPDATE ได้ (approve/reject)
CREATE POLICY "correction_requests_update_approver"
  ON correction_requests FOR UPDATE
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate', 'hr_admin', 'supervisor')
  );

---

-- Diligence Counters (เบี้ยขยัน)
CREATE TABLE employee_diligence_counters (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID NOT NULL REFERENCES employees(id),
  year INTEGER NOT NULL,
  month INTEGER NOT NULL CHECK (month BETWEEN 1 AND 12),

  -- Counters (รวมกัน ≥3 = ตัดเบี้ย)
  late_count INTEGER NOT NULL DEFAULT 0,
  forgot_count INTEGER NOT NULL DEFAULT 0,
  correction_count INTEGER NOT NULL DEFAULT 0,
  sick_leave_count INTEGER NOT NULL DEFAULT 0, -- ≥1 = ตัดเบี้ย

  -- Result
  is_forfeited BOOLEAN NOT NULL DEFAULT false,
  forfeited_reason TEXT,

  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE(employee_id, year, month)
);

-- Auto-update updated_at
CREATE TRIGGER diligence_counters_updated_at
  BEFORE UPDATE ON employee_diligence_counters
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Index
CREATE INDEX diligence_counters_employee_idx ON employee_diligence_counters(employee_id);
CREATE INDEX diligence_counters_period_idx ON employee_diligence_counters(year, month);

-- RLS
ALTER TABLE employee_diligence_counters ENABLE ROW LEVEL SECURITY;

-- Owner/Delegate/HR Admin/Finance เห็นทั้งหมด
CREATE POLICY "diligence_counters_read_admin"
  ON employee_diligence_counters FOR SELECT
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate', 'hr_admin', 'finance')
  );

-- Staff เห็นเฉพาะตัวเอง
CREATE POLICY "diligence_counters_read_self"
  ON employee_diligence_counters FOR SELECT
  TO authenticated
  USING (employee_id = auth.uid());

-- HR Admin/System update ได้
CREATE POLICY "diligence_counters_write_admin"
  ON employee_diligence_counters FOR ALL
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate', 'hr_admin')
  );