-- Cost Centers
CREATE TABLE cost_centers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('main', 'support')),
  gps_latitude DECIMAL(10, 7),
  gps_longitude DECIMAL(10, 7),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- RLS
ALTER TABLE cost_centers ENABLE ROW LEVEL SECURITY;

-- ทุก role อ่านได้
CREATE POLICY "cost_centers_read_all"
  ON cost_centers FOR SELECT
  TO authenticated
  USING (true);

-- เฉพาะ owner/delegate/hr_admin แก้ได้
CREATE POLICY "cost_centers_write_admin"
  ON cost_centers FOR ALL
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate', 'hr_admin')
  );

-- Seed: 8 Cost Centers
INSERT INTO cost_centers (code, name, type, gps_latitude, gps_longitude) VALUES
  ('CC-HQ-WS', 'สำนักงานใหญ่ ขายส่ง', 'main', 14.886239, 103.492307),
  ('CC-01', 'สำนักงานใหญ่ ขายปลีก', 'main', 14.8864189, 103.4919395),
  ('CC-04', 'สาขา 4', 'main', 14.8732376, 103.5060382),
  ('CC-SUPPORT-HR', 'ฝ่าย HR', 'support', NULL, NULL),
  ('CC-SUPPORT-FIN', 'ฝ่ายการเงิน', 'support', NULL, NULL),
  ('CC-SUPPORT-IT', 'ฝ่าย IT', 'support', NULL, NULL),
  ('CC-SUPPORT-WH', 'ฝ่ายคลังสินค้า', 'support', NULL, NULL),
  ('CC-SUPPORT-FAC', 'ฝ่าย Facility', 'support', NULL, NULL);