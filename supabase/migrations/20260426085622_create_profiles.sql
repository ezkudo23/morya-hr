-- Profiles (link Supabase Auth → employees)
CREATE TABLE profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  employee_id UUID NOT NULL UNIQUE REFERENCES employees(id),
  role TEXT NOT NULL CHECK (role IN (
    'owner', 'owner_delegate', 'hr_admin', 'finance',
    'it_support', 'supervisor', 'staff', 'pc_staff'
  )),
  is_active BOOLEAN NOT NULL DEFAULT true,
  last_login TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Auto-update updated_at
CREATE TRIGGER profiles_updated_at
  BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- RLS
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- ดูของตัวเองได้
CREATE POLICY "profiles_read_self"
  ON profiles FOR SELECT
  TO authenticated
  USING (id = auth.uid());

-- Owner/Delegate/HR Admin/IT ดูทั้งหมดได้
CREATE POLICY "profiles_read_admin"
  ON profiles FOR SELECT
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate', 'hr_admin', 'it_support')
  );

-- Owner/Delegate/IT แก้ได้
CREATE POLICY "profiles_write_admin"
  ON profiles FOR ALL
  TO authenticated
  USING (
    (auth.jwt() ->> 'role') IN ('owner', 'owner_delegate', 'it_support')
  );

-- Auto-create profile เมื่อ user สมัคร (trigger)
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  -- Profile จะถูกสร้างโดย HR Admin/IT ไม่ใช่ auto
  -- trigger นี้ไว้ log เท่านั้น
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;