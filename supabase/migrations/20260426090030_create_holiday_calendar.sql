-- Holiday Calendar
CREATE TABLE holiday_calendar (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  date DATE NOT NULL UNIQUE,
  name TEXT NOT NULL,
  year INTEGER NOT NULL GENERATED ALWAYS AS (EXTRACT(YEAR FROM date)::INTEGER) STORED,
  type TEXT NOT NULL CHECK (type IN (
    'closed',           -- ร้านปิด
    'open_substitute',  -- เปิด + ได้ token แทน
    'open_changed'      -- เปิด + OT 2x + consent
  )),
  is_store_open BOOLEAN NOT NULL GENERATED ALWAYS AS (type != 'closed') STORED,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index
CREATE INDEX holiday_calendar_date_idx ON holiday_calendar(date);
CREATE INDEX holiday_calendar_year_idx ON holiday_calendar(year);

-- RLS
ALTER TABLE holiday_calendar ENABLE ROW LEVEL SECURITY;

-- ทุก role อ่านได้
CREATE POLICY "holiday_calendar_read_all"
  ON holiday_calendar FOR SELECT
  TO authenticated
  USING (true);

-- Owner/Delegate/HR Admin แก้ได้
CREATE POLICY "holiday_calendar_write_admin"
  ON holiday_calendar FOR ALL
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate', 'hr_admin')
  );

-- Seed: วันหยุด 2569 (ค.ศ. 2026)
INSERT INTO holiday_calendar (date, name, type) VALUES
  ('2026-01-01', 'วันขึ้นปีใหม่', 'closed'),
  ('2026-02-12', 'วันมาฆบูชา', 'closed'),
  ('2026-04-06', 'วันจักรี', 'closed'),
  ('2026-04-13', 'วันสงกรานต์', 'closed'),
  ('2026-04-14', 'วันสงกรานต์', 'closed'),
  ('2026-04-15', 'วันสงกรานต์', 'closed'),
  ('2026-05-01', 'วันแรงงานแห่งชาติ', 'closed'),
  ('2026-05-04', 'วันฉัตรมงคล', 'closed'),
  ('2026-05-11', 'วันวิสาขบูชา', 'closed'),
  ('2026-06-03', 'วันเฉลิมพระชนมพรรษา ร.10', 'closed'),
  ('2026-07-09', 'วันอาสาฬหบูชา', 'closed'),
  ('2026-07-10', 'วันเข้าพรรษา', 'closed'),
  ('2026-07-28', 'วันเฉลิมพระชนมพรรษา ร.10 (ชดเชย)', 'closed'),
  ('2026-08-12', 'วันแม่แห่งชาติ', 'closed'),
  ('2026-10-13', 'วันคล้ายวันสวรรคต ร.9', 'closed'),
  ('2026-10-23', 'วันปิยมหาราช', 'closed'),
  ('2026-12-05', 'วันพ่อแห่งชาติ', 'closed'),
  ('2026-12-10', 'วันรัฐธรรมนูญ', 'closed'),
  ('2026-12-31', 'วันสิ้นปี', 'closed');