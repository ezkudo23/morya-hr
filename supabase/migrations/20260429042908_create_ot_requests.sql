-- Table: ot_requests
-- หน้าที่: เก็บคำขอ OT ทุกรายการ
-- Date: 29 เม.ย. 2569

CREATE TABLE IF NOT EXISTS ot_requests (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id         UUID NOT NULL REFERENCES employees(id),

  -- วันและเวลา OT
  ot_date             DATE NOT NULL,
  start_time          TIME NOT NULL,
  end_time            TIME NOT NULL,
  hours               DECIMAL(4,1) NOT NULL,  -- คำนวณจาก start-end

  -- ประเภท OT
  ot_type             TEXT NOT NULL CHECK (ot_type IN (
                        'normal',    -- วันทำงานปกติ 1.5x
                        'holiday'    -- วันหยุด 3x
                      )),

  -- อัตราค่า OT (DB-driven — ปรับได้จาก config)
  rate_multiplier     DECIMAL(4,2) NOT NULL DEFAULT 1.5,
  hourly_rate         DECIMAL(10,2),          -- สำหรับ fix rate เช่น เภสัชกร 150/ชม.
  is_fixed_rate       BOOLEAN NOT NULL DEFAULT false,

  -- เหตุผลและหลักฐาน
  reason              TEXT,
  evidence_url        TEXT,                   -- optional

  -- Approval (DB-driven chain)
  status              TEXT NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending','approved','rejected','cancelled')),
  approval_step       INTEGER NOT NULL DEFAULT 1,
  approval_step_max   INTEGER NOT NULL DEFAULT 2,  -- default: Sup→Owner
  current_approver_id UUID REFERENCES auth.users(id),
  approver_chain      JSONB NOT NULL DEFAULT '[]',
  approver_note       TEXT,
  approved_at         TIMESTAMPTZ,
  rejected_at         TIMESTAMPTZ,

  -- Metadata
  submitted_within_window  BOOLEAN NOT NULL DEFAULT true,  -- ยื่นภายใน 72 ชม.
  is_backdate              BOOLEAN NOT NULL DEFAULT false,

  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_ot_requests_employee_id ON ot_requests(employee_id);
CREATE INDEX idx_ot_requests_status      ON ot_requests(status);
CREATE INDEX idx_ot_requests_ot_date     ON ot_requests(ot_date);
CREATE INDEX idx_ot_requests_approver    ON ot_requests(current_approver_id);

-- Auto-update updated_at
CREATE TRIGGER set_ot_requests_updated_at
  BEFORE UPDATE ON ot_requests
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- RLS
ALTER TABLE ot_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "owner_all" ON ot_requests
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
        AND profiles.role IN ('owner', 'owner_delegate', 'hr_admin')
    )
  );

CREATE POLICY "supervisor_team" ON ot_requests
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM employees e
      JOIN profiles p ON p.employee_id = e.id
      WHERE e.id = ot_requests.employee_id
        AND e.supervisor_id = (
          SELECT emp.id FROM employees emp
          JOIN profiles pr ON pr.employee_id = emp.id
          WHERE pr.id = auth.uid()
        )
    )
  );

CREATE POLICY "staff_own" ON ot_requests
  FOR SELECT TO authenticated
  USING (
    employee_id = (
      SELECT e.id FROM employees e
      JOIN profiles p ON p.employee_id = e.id
      WHERE p.id = auth.uid()
    )
  );

CREATE POLICY "staff_insert" ON ot_requests
  FOR INSERT TO authenticated
  WITH CHECK (
    employee_id = (
      SELECT e.id FROM employees e
      JOIN profiles p ON p.employee_id = e.id
      WHERE p.id = auth.uid()
    )
  );

CREATE POLICY "approver_update" ON ot_requests
  FOR UPDATE TO authenticated
  USING (current_approver_id = auth.uid());

-- Comments
COMMENT ON TABLE  ot_requests IS 'คำขอ OT ทุกรายการ — rate และ approval chain ปรับได้จาก DB';
COMMENT ON COLUMN ot_requests.rate_multiplier IS 'อัตราคูณ: 1.5=ปกติ, 3.0=วันหยุด (DB-driven)';
COMMENT ON COLUMN ot_requests.hourly_rate     IS 'fix rate บาท/ชม. — ใช้เมื่อ is_fixed_rate=true เช่น เภสัชกร 150';
COMMENT ON COLUMN ot_requests.is_fixed_rate   IS 'true = ใช้ hourly_rate แทน rate_multiplier (เช่น เภสัชกร D17)';
COMMENT ON COLUMN ot_requests.approval_step_max IS 'จำนวน step ที่ต้องผ่าน — configurable จาก DB';
COMMENT ON COLUMN ot_requests.submitted_within_window IS 'ยื่นภายใน 72 ชม. หลัง ot_date (D12)';