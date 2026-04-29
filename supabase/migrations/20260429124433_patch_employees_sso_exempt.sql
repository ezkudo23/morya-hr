-- Migration: patch_employees_sso_exempt
-- หน้าที่: เพิ่ม is_sso_exempt flag — กรรมการบริษัทไม่เข้า SSO
-- Date: 29 เม.ย. 2569

ALTER TABLE employees
ADD COLUMN IF NOT EXISTS is_sso_exempt BOOLEAN NOT NULL DEFAULT false;

-- อมร และ ไนซ์ = กรรมการ ไม่เข้า SSO
UPDATE employees SET is_sso_exempt = true
WHERE employee_code IN ('MR-001', 'MR-002');