-- Audit Logs (Append-only — ห้าม UPDATE/DELETE)
CREATE TABLE audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Level & Category
  level INTEGER NOT NULL CHECK (level IN (1, 2)),
  category TEXT NOT NULL CHECK (category IN (
    'auth', 'employee', 'attendance', 'leave', 'ot',
    'payroll', 'tax', 'system', 'pdpa', 'emergency'
  )),
  action TEXT NOT NULL,

  -- Actor
  actor_id UUID REFERENCES auth.users(id),
  actor_role TEXT,
  actor_name TEXT,

  -- Target
  target_type TEXT,
  target_id UUID,
  target_identifier TEXT,

  -- Changes
  changes_before JSONB,
  changes_after JSONB,
  reason TEXT,

  -- Context
  ip_address TEXT,
  gps_latitude DECIMAL(10, 7),
  gps_longitude DECIMAL(10, 7),
  session_id TEXT,
  user_agent TEXT,

  -- Retention
  legal_hold BOOLEAN NOT NULL DEFAULT false,
  retention_until DATE NOT NULL,

  -- Timestamp (immutable)
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index สำหรับ search
CREATE INDEX audit_logs_actor_idx ON audit_logs(actor_id);
CREATE INDEX audit_logs_category_idx ON audit_logs(category);
CREATE INDEX audit_logs_created_at_idx ON audit_logs(created_at);
CREATE INDEX audit_logs_target_idx ON audit_logs(target_type, target_id);
CREATE INDEX audit_logs_legal_hold_idx ON audit_logs(legal_hold) WHERE legal_hold = true;

-- RLS
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

-- Owner/Delegate เห็นทั้งหมด
CREATE POLICY "audit_logs_read_owner"
  ON audit_logs FOR SELECT
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate')
  );

-- HR Admin เห็นเฉพาะ category ที่เกี่ยวข้อง
CREATE POLICY "audit_logs_read_hr"
  ON audit_logs FOR SELECT
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') = 'hr_admin'
    AND category IN ('employee', 'attendance', 'leave', 'ot', 'pdpa')
  );

-- Finance เห็นเฉพาะ payroll/tax
CREATE POLICY "audit_logs_read_finance"
  ON audit_logs FOR SELECT
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') = 'finance'
    AND category IN ('payroll', 'tax')
  );

-- IT เห็นเฉพาะ system/auth
CREATE POLICY "audit_logs_read_it"
  ON audit_logs FOR SELECT
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') = 'it_support'
    AND category IN ('auth', 'system')
  );

-- INSERT ได้ทุก authenticated user (ผ่าน service role เท่านั้น)
CREATE POLICY "audit_logs_insert"
  ON audit_logs FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- ห้าม UPDATE และ DELETE ทุกกรณี (Append-only)
CREATE RULE audit_logs_no_update AS
  ON UPDATE TO audit_logs DO INSTEAD NOTHING;

CREATE RULE audit_logs_no_delete AS
  ON DELETE TO audit_logs DO INSTEAD NOTHING;

-- Function: สร้าง audit log
CREATE OR REPLACE FUNCTION create_audit_log(
  p_level INTEGER,
  p_category TEXT,
  p_action TEXT,
  p_actor_id UUID,
  p_actor_role TEXT,
  p_actor_name TEXT,
  p_target_type TEXT DEFAULT NULL,
  p_target_id UUID DEFAULT NULL,
  p_target_identifier TEXT DEFAULT NULL,
  p_changes_before JSONB DEFAULT NULL,
  p_changes_after JSONB DEFAULT NULL,
  p_reason TEXT DEFAULT NULL,
  p_ip_address TEXT DEFAULT NULL,
  p_gps_latitude DECIMAL DEFAULT NULL,
  p_gps_longitude DECIMAL DEFAULT NULL,
  p_session_id TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
  v_retention_until DATE;
  v_log_id UUID;
BEGIN
  -- คำนวณ retention_until ตาม level
  v_retention_until := CASE p_level
    WHEN 1 THEN CURRENT_DATE + INTERVAL '1 year'
    WHEN 2 THEN CURRENT_DATE + INTERVAL '2 years'
    ELSE CURRENT_DATE + INTERVAL '1 year'
  END;

  INSERT INTO audit_logs (
    level, category, action,
    actor_id, actor_role, actor_name,
    target_type, target_id, target_identifier,
    changes_before, changes_after, reason,
    ip_address, gps_latitude, gps_longitude,
    session_id, retention_until
  ) VALUES (
    p_level, p_category, p_action,
    p_actor_id, p_actor_role, p_actor_name,
    p_target_type, p_target_id, p_target_identifier,
    p_changes_before, p_changes_after, p_reason,
    p_ip_address, p_gps_latitude, p_gps_longitude,
    p_session_id, v_retention_until
  ) RETURNING id INTO v_log_id;

  RETURN v_log_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;