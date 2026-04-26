-- Consent Records (PDPA)
CREATE TABLE consent_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID NOT NULL REFERENCES employees(id),

  -- Consent Type
  consent_type TEXT NOT NULL CHECK (consent_type IN (
    'employment',       -- ข้อมูลการจ้างงาน
    'payroll',          -- ข้อมูลเงินเดือน
    'attendance',       -- บันทึกเวลา + GPS
    'biometric',        -- ข้อมูลชีวมิติ (ถ้ามีในอนาคต)
    'marketing',        -- การตลาด (ถ้ามี)
    'third_party'       -- ส่งข้อมูลบุคคลที่สาม (ปกส., สรรพากร)
  )),

  purpose TEXT NOT NULL,
  scope JSONB NOT NULL DEFAULT '{}',
  version TEXT NOT NULL DEFAULT '1.0',

  -- Grant
  granted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  granted_ip TEXT,
  granted_via TEXT CHECK (granted_via IN ('liff', 'admin_panel', 'paper')),

  -- Withdraw
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN (
    'active', 'withdrawn', 'expired'
  )),
  withdrawn_at TIMESTAMPTZ,
  withdrawal_reason TEXT,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index
CREATE INDEX consent_records_employee_idx ON consent_records(employee_id);
CREATE INDEX consent_records_status_idx ON consent_records(status);
CREATE INDEX consent_records_type_idx ON consent_records(consent_type);

-- RLS
ALTER TABLE consent_records ENABLE ROW LEVEL SECURITY;

CREATE POLICY "consent_records_read_admin"
  ON consent_records FOR SELECT
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate', 'hr_admin')
  );

CREATE POLICY "consent_records_read_self"
  ON consent_records FOR SELECT
  TO authenticated
  USING (employee_id = auth.uid());

CREATE POLICY "consent_records_insert_admin"
  ON consent_records FOR INSERT
  TO authenticated
  WITH CHECK (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate', 'hr_admin')
    OR employee_id = auth.uid()
  );

CREATE POLICY "consent_records_update_admin"
  ON consent_records FOR UPDATE
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate', 'hr_admin')
  );

---

-- DSR Requests (Data Subject Requests)
CREATE TABLE dsr_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID NOT NULL REFERENCES employees(id),

  request_type TEXT NOT NULL CHECK (request_type IN (
    'access',       -- ขอดูข้อมูล
    'rectify',      -- ขอแก้ไข
    'erase',        -- ขอลบ
    'restrict',     -- ขอระงับ
    'portability',  -- ขอโอนข้อมูล
    'object'        -- คัดค้าน
  )),

  description TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN (
    'pending', 'in_progress', 'completed', 'rejected'
  )),

  -- SLA: 30 วัน
  due_date DATE NOT NULL DEFAULT (CURRENT_DATE + INTERVAL '30 days')::DATE,

  handled_by UUID REFERENCES auth.users(id),
  response TEXT,
  completed_at TIMESTAMPTZ,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Auto-update updated_at
CREATE TRIGGER dsr_requests_updated_at
  BEFORE UPDATE ON dsr_requests
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Index
CREATE INDEX dsr_requests_employee_idx ON dsr_requests(employee_id);
CREATE INDEX dsr_requests_status_idx ON dsr_requests(status);
CREATE INDEX dsr_requests_due_date_idx ON dsr_requests(due_date);

-- RLS
ALTER TABLE dsr_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "dsr_requests_read_admin"
  ON dsr_requests FOR SELECT
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate', 'hr_admin')
  );

CREATE POLICY "dsr_requests_read_self"
  ON dsr_requests FOR SELECT
  TO authenticated
  USING (employee_id = auth.uid());

CREATE POLICY "dsr_requests_insert_self"
  ON dsr_requests FOR INSERT
  TO authenticated
  WITH CHECK (employee_id = auth.uid());

CREATE POLICY "dsr_requests_update_admin"
  ON dsr_requests FOR UPDATE
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate', 'hr_admin')
  );

---

-- Notifications Log
CREATE TABLE notifications_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID REFERENCES employees(id), -- NULL = broadcast

  -- Type & Level
  type TEXT NOT NULL CHECK (type IN (
    'check_in_reminder',
    'check_out_reminder',
    'leave_approved',
    'leave_rejected',
    'ot_approved',
    'ot_rejected',
    'correction_approved',
    'correction_rejected',
    'payslip_ready',
    'diligence_warning',
    'diligence_forfeited',
    'payroll_approved',
    'system_alert',
    'daily_digest'
  )),
  level TEXT NOT NULL CHECK (level IN (
    'critical', 'high', 'medium', 'low', 'info'
  )),

  -- Content
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  data JSONB DEFAULT '{}',

  -- LINE
  line_message_id TEXT,
  sent_via TEXT CHECK (sent_via IN ('line', 'liff', 'both')),

  -- Status
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN (
    'pending', 'sent', 'failed', 'skipped'
  )),
  sent_at TIMESTAMPTZ,
  error_message TEXT,

  -- Quiet Hours (22:00-08:00)
  is_quiet_hour BOOLEAN NOT NULL DEFAULT false,
  scheduled_at TIMESTAMPTZ, -- ถ้า quiet hour = ส่งตอน 08:00

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index
CREATE INDEX notifications_log_employee_idx ON notifications_log(employee_id);
CREATE INDEX notifications_log_status_idx ON notifications_log(status);
CREATE INDEX notifications_log_created_at_idx ON notifications_log(created_at);
CREATE INDEX notifications_log_scheduled_idx ON notifications_log(scheduled_at)
  WHERE scheduled_at IS NOT NULL;

-- RLS
ALTER TABLE notifications_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "notifications_log_read_admin"
  ON notifications_log FOR SELECT
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate', 'hr_admin', 'it_support')
  );

CREATE POLICY "notifications_log_read_self"
  ON notifications_log FOR SELECT
  TO authenticated
  USING (employee_id = auth.uid());

CREATE POLICY "notifications_log_insert"
  ON notifications_log FOR INSERT
  TO authenticated
  WITH CHECK (true);