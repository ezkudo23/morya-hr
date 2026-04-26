-- Shifts
CREATE TABLE shifts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cost_center_id UUID NOT NULL REFERENCES cost_centers(id),
  name TEXT NOT NULL,
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  is_overnight BOOLEAN NOT NULL DEFAULT false, -- กะข้ามคืน
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- RLS
ALTER TABLE shifts ENABLE ROW LEVEL SECURITY;

-- ทุก role อ่านได้
CREATE POLICY "shifts_read_all"
  ON shifts FOR SELECT
  TO authenticated
  USING (true);

-- Owner/Delegate/HR Admin แก้ได้
CREATE POLICY "shifts_write_admin"
  ON shifts FOR ALL
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate', 'hr_admin')
  );

-- Seed: กะทำงานทุก CC
INSERT INTO shifts (cost_center_id, name, start_time, end_time) VALUES
  -- CC-HQ-WS (ขายส่ง)
  ((SELECT id FROM cost_centers WHERE code = 'CC-HQ-WS'),
   'SHIFT_WS', '08:30', '17:30'),

  -- CC-01 (ขายปลีก HQ)
  ((SELECT id FROM cost_centers WHERE code = 'CC-01'),
   'Morning', '08:30', '17:30'),
  ((SELECT id FROM cost_centers WHERE code = 'CC-01'),
   'Closing', '10:00', '19:00'),
  ((SELECT id FROM cost_centers WHERE code = 'CC-01'),
   'Sunday', '08:30', '17:30'),

  -- CC-04 (สาขา 4)
  ((SELECT id FROM cost_centers WHERE code = 'CC-04'),
   'Morning', '09:00', '18:00'),
  ((SELECT id FROM cost_centers WHERE code = 'CC-04'),
   'Closing', '12:00', '21:00');

-- Employee Shifts (ตารางกะรายคน)
CREATE TABLE employee_shifts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID NOT NULL REFERENCES employees(id),
  shift_id UUID NOT NULL REFERENCES shifts(id),
  work_date DATE NOT NULL,
  is_holiday_pivot BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(employee_id, work_date) -- 1 คน 1 วัน มีได้ 1 กะ
);

-- Index
CREATE INDEX employee_shifts_employee_date_idx ON employee_shifts(employee_id, work_date);
CREATE INDEX employee_shifts_date_idx ON employee_shifts(work_date);

-- RLS
ALTER TABLE employee_shifts ENABLE ROW LEVEL SECURITY;

-- Owner/Delegate/HR Admin เห็นทั้งหมด
CREATE POLICY "employee_shifts_read_admin"
  ON employee_shifts FOR SELECT
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate', 'hr_admin')
  );

-- Supervisor เห็นเฉพาะทีม
CREATE POLICY "employee_shifts_read_supervisor"
  ON employee_shifts FOR SELECT
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') = 'supervisor'
    AND employee_id IN (
      SELECT id FROM employees WHERE supervisor_id = auth.uid()
    )
  );

-- Staff เห็นเฉพาะตัวเอง
CREATE POLICY "employee_shifts_read_self"
  ON employee_shifts FOR SELECT
  TO authenticated
  USING (employee_id = auth.uid());

-- Owner/Delegate/HR Admin แก้ได้
CREATE POLICY "employee_shifts_write_admin"
  ON employee_shifts FOR ALL
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate', 'hr_admin')
  );