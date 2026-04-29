-- Migration: reseed_employees
-- หน้าที่: ล้างข้อมูลเดิมแล้ว insert ใหม่จาก Humansoft + manual data
-- Date: 29 เม.ย. 2569

-- ────────────────────────────────────────────
-- 0. เพิ่ม columns ที่ยังไม่มีใน schema
-- ────────────────────────────────────────────
ALTER TABLE employees
ADD COLUMN IF NOT EXISTS is_attendance_exempt BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE cost_centers
ADD COLUMN IF NOT EXISTS gps_radius_meters INTEGER NOT NULL DEFAULT 100;

-- ────────────────────────────────────────────
-- 1. ล้างข้อมูลเดิม (cascade)
-- ────────────────────────────────────────────
TRUNCATE TABLE employee_diligence_counters CASCADE;
TRUNCATE TABLE attendance_logs CASCADE;
TRUNCATE TABLE leave_requests CASCADE;
TRUNCATE TABLE leave_balances CASCADE;
TRUNCATE TABLE ot_requests CASCADE;
TRUNCATE TABLE payroll_details CASCADE;
TRUNCATE TABLE payroll_runs CASCADE;
TRUNCATE TABLE profiles CASCADE;
TRUNCATE TABLE employees CASCADE;
TRUNCATE TABLE cost_centers CASCADE;

-- ────────────────────────────────────────────
-- 2. Cost Centers (UUID 1-9)
-- ────────────────────────────────────────────
INSERT INTO cost_centers (id, code, name, type, gps_latitude, gps_longitude, gps_radius_meters, is_active) VALUES
  ('420626ba-9679-45a9-a6af-8440ac908a07', 'HQ-00',          'สำนักงานใหญ่ ค้าส่ง',  'main',    14.886239,  103.492307,  100, true),
  ('e257f721-a065-46d5-ae9d-29bb98fcb1dd', 'HQ-01',          'สำนักงานใหญ่ ค้าปลีก', 'main',    14.8864189, 103.4919395, 100, true),
  ('5094ff92-85f6-4262-8701-b3fc11b6d2ec', 'CC-04',          'สาขา 3',                'main',    14.8732376, 103.5060382, 100, true),
  ('d3b64365-f632-4009-9b73-16324cf70398', 'CC-SUPPORT-ADM', 'Admin Support',          'support', 14.886239,  103.492307,  100, true),
  ('1f2296ba-0f80-45cf-b66b-7e22236b5797', 'CC-SUPPORT-FIN', 'Finance Support',        'support', 14.886239,  103.492307,  100, true),
  ('661224c5-0da8-4265-8e53-2600b3723c25', 'CC-SUPPORT-FAC', 'Facility Support',       'support', 14.886239,  103.492307,  100, true),
  ('236a2da0-9995-4182-a394-a009fa5d4bbd', 'CC-SUPPORT-IT',  'IT Support',             'support', 14.886239,  103.492307,  100, true),
  ('98a65ba3-f5e1-4f6c-b7a6-83814f09bce5', 'CC-MGT',         'Management',             'support', 14.886239,  103.492307,  100, true),
  ('fe136849-5c0d-4772-aff3-04b7c8851d47', 'CC-PC',          'PC Staff',               'support', 14.886239,  103.492307,  100, true);

-- ────────────────────────────────────────────
-- 3. Employees (UUID 10-41)
-- ────────────────────────────────────────────

-- Owner & Delegates
INSERT INTO employees (id, employee_code, full_name_th, full_name_en, nickname, tax_id,
  role, employment_type, employment_status, cost_center_id, supervisor_id,
  salary_base, hire_date, bank_name, bank_account, phone, is_attendance_exempt)
VALUES
  ('77ff2b09-34ab-4e3f-9640-373e761cd761',
   'MR-001', 'อมร เกียรติคุณรัตน์', 'Amorn Kiatkunnarat', 'เฮีย', '1329900065234',
   'owner', 'director_salary', 'active',
   '98a65ba3-f5e1-4f6c-b7a6-83814f09bce5', NULL,
   0, '2014-10-21', NULL, NULL, NULL, true),

  ('b7c81025-09fc-4b30-a23b-0f273441c7b0',
   'MR-002', 'ณภิญา ลีลาอภิฤดี', NULL, 'ไนซ์', '1329900159263',
   'owner_delegate', 'director_salary', 'active',
   '98a65ba3-f5e1-4f6c-b7a6-83814f09bce5', NULL,
   0, '2014-10-21', NULL, NULL, NULL, true),

  ('3669abbe-038b-4b5b-b2c2-38ab88f64873',
   'MR-003', 'ศศิ เกียรติคุณรัตน์', NULL, 'จิว', '1329900201529',
   'owner_delegate', 'director_salary', 'active',
   '98a65ba3-f5e1-4f6c-b7a6-83814f09bce5', NULL,
   0, '2014-10-21', NULL, NULL, NULL, true);

-- Supervisors
INSERT INTO employees (id, employee_code, full_name_th, full_name_en, nickname, tax_id,
  role, employment_type, employment_status, cost_center_id, supervisor_id,
  salary_base, hire_date, bank_name, bank_account, phone, is_attendance_exempt)
VALUES
  ('bc049c43-bf92-4fac-8e15-4c64fbdb75a2',
   'MR-004', 'กษิดิศ สงึมรัมย์', 'Kasidit Sa-ngeumrum', 'ค๊อป', '1329900502081',
   'supervisor', 'regular_salary', 'active',
   'e257f721-a065-46d5-ae9d-29bb98fcb1dd',
   '77ff2b09-34ab-4e3f-9640-373e761cd761',
   31000, '2022-07-01', 'SCB', '899-2-63208-4', '875680378', false),

  ('a3034aa4-bb08-422c-8d49-36d88d242f56',
   'MR-005', 'ภัทราภรณ์ ปัสสาวะกัง', NULL, NULL, '1110200111105',
   'supervisor', 'regular_salary', 'active',
   '420626ba-9679-45a9-a6af-8440ac908a07',
   '77ff2b09-34ab-4e3f-9640-373e761cd761',
   0, '2014-10-21', NULL, NULL, NULL, false),

  ('305c8f0b-bcd2-450f-9a80-1d963a866f31',
   'MR-006', 'ดวงหทัย ปวนใต้', NULL, NULL, '3500900654678',
   'supervisor', 'regular_salary', 'active',
   '420626ba-9679-45a9-a6af-8440ac908a07',
   '77ff2b09-34ab-4e3f-9640-373e761cd761',
   0, '2014-10-21', NULL, NULL, NULL, false),

  ('cf158463-0549-40eb-8929-732b67e18f07',
   'MR-007', 'ศิราพร สิทธิรัมย์', NULL, NULL, '1310900096760',
   'supervisor', 'regular_salary', 'active',
   '5094ff92-85f6-4262-8701-b3fc11b6d2ec',
   '77ff2b09-34ab-4e3f-9640-373e761cd761',
   0, '2014-10-21', NULL, NULL, NULL, false);

-- HR Admin & Finance
INSERT INTO employees (id, employee_code, full_name_th, full_name_en, nickname, tax_id,
  role, employment_type, employment_status, cost_center_id, supervisor_id,
  salary_base, hire_date, bank_name, bank_account, phone, is_attendance_exempt)
VALUES
  ('c481e103-a89f-4572-8e6f-425d182c580b',
   'MR-008', 'เกวลี สุระวิทย์', NULL, NULL, '1329900469041',
   'hr_admin', 'regular_salary', 'active',
   'd3b64365-f632-4009-9b73-16324cf70398',
   '77ff2b09-34ab-4e3f-9640-373e761cd761',
   0, '2014-10-21', NULL, NULL, NULL, false),

  ('6c936c97-9d54-4613-aa0a-146e3548944b',
   'MR-009', 'พรนภา โนนสาลี', NULL, NULL, '1329900371106',
   'finance', 'regular_salary', 'active',
   '1f2296ba-0f80-45cf-b66b-7e22236b5797',
   '77ff2b09-34ab-4e3f-9640-373e761cd761',
   0, '2014-10-21', NULL, NULL, NULL, false),

  ('2191aa7c-b867-48f0-92b2-16f584b9f9f9',
   'MR-010', 'รัตนาวดี มั่นหมาย', NULL, NULL, '1329900270393',
   'finance', 'regular_salary', 'active',
   '1f2296ba-0f80-45cf-b66b-7e22236b5797',
   '77ff2b09-34ab-4e3f-9640-373e761cd761',
   0, '2014-10-21', NULL, NULL, NULL, false);

-- Staff HQ-00
INSERT INTO employees (id, employee_code, full_name_th, full_name_en, nickname, tax_id,
  role, employment_type, employment_status, cost_center_id, supervisor_id,
  salary_base, hire_date, bank_name, bank_account, phone, is_attendance_exempt)
VALUES
  ('effdab9a-3390-4bf2-b939-dc93e0221583',
   'MR-011', 'ปรเมศร์ มีทอง', NULL, NULL, '1329900802794',
   'staff', 'regular_salary', 'active',
   '420626ba-9679-45a9-a6af-8440ac908a07',
   'a3034aa4-bb08-422c-8d49-36d88d242f56',
   0, '2014-10-21', NULL, NULL, NULL, false),

  ('b0bc73da-dd1e-4f52-9240-5497796190db',
   'MR-012', 'สุวิมล แสงสุข', NULL, NULL, '1329900691984',
   'staff', 'regular_salary', 'active',
   '420626ba-9679-45a9-a6af-8440ac908a07',
   'a3034aa4-bb08-422c-8d49-36d88d242f56',
   0, '2014-10-21', NULL, NULL, NULL, false),

  ('2f2fc6f1-b17a-40ce-9902-f64976cf97d6',
   'MR-013', 'พนัสโชค มีทองแสน', NULL, NULL, '1329900837253',
   'staff', 'regular_salary', 'active',
   '420626ba-9679-45a9-a6af-8440ac908a07',
   'a3034aa4-bb08-422c-8d49-36d88d242f56',
   0, '2014-10-21', NULL, NULL, NULL, false),

  ('d9bd4dd2-7296-4ca5-a56c-e1fb07062c58',
   'MR-014', 'ณัฐรียา พิมพ์สวัสดิ์', NULL, NULL, '1329900137821',
   'staff', 'regular_salary', 'active',
   '420626ba-9679-45a9-a6af-8440ac908a07',
   '305c8f0b-bcd2-450f-9a80-1d963a866f31',
   0, '2014-10-21', NULL, NULL, NULL, false),

  ('ca18c273-d96c-40f2-a55f-f24076e3973a',
   'MR-015', 'อรรถพล คำเบ้า', NULL, NULL, '1330400387331',
   'staff', 'regular_salary', 'active',
   '420626ba-9679-45a9-a6af-8440ac908a07',
   '305c8f0b-bcd2-450f-9a80-1d963a866f31',
   0, '2014-10-21', NULL, NULL, NULL, false),

  ('568b558d-558c-4d27-8012-f14dffdd0c62',
   'MR-016', 'ศริพงศ์ ทองแดง', NULL, NULL, '1329900242161',
   'staff', 'regular_salary', 'active',
   '420626ba-9679-45a9-a6af-8440ac908a07',
   '305c8f0b-bcd2-450f-9a80-1d963a866f31',
   0, '2014-10-21', NULL, NULL, NULL, false),

  ('1159247e-f30c-449f-a304-da5e18af3e9f',
   'MR-017', 'สุจิตรา ทรายทอง', NULL, NULL, '3500900550082',
   'staff', 'regular_salary', 'active',
   '420626ba-9679-45a9-a6af-8440ac908a07',
   '305c8f0b-bcd2-450f-9a80-1d963a866f31',
   0, '2014-10-21', NULL, NULL, NULL, false),

  ('0cb9f508-5d35-4c44-b08d-a59e652eb145',
   'MR-018', 'ศิริรัตน์ ผิวขาว', NULL, NULL, '3320100624288',
   'staff', 'regular_salary', 'active',
   '420626ba-9679-45a9-a6af-8440ac908a07',
   '305c8f0b-bcd2-450f-9a80-1d963a866f31',
   0, '2014-10-21', NULL, NULL, NULL, false),

  ('ee906a80-4857-4ebe-9d3f-c74ca16c142f',
   'MR-019', 'สุนัย เลือดขุนทด', NULL, NULL, '1329900464317',
   'staff', 'regular_salary', 'active',
   '420626ba-9679-45a9-a6af-8440ac908a07',
   'a3034aa4-bb08-422c-8d49-36d88d242f56',
   0, '2014-10-21', NULL, NULL, NULL, false),

  ('5868cb97-50fd-42f0-a9bf-f1cc8cb2c064',
   'MR-020', 'ธนภัทร ขอชนะ', NULL, NULL, '1329900743411',
   'staff', 'regular_salary', 'active',
   '420626ba-9679-45a9-a6af-8440ac908a07',
   'a3034aa4-bb08-422c-8d49-36d88d242f56',
   0, '2014-10-21', NULL, NULL, NULL, false),

  ('7afce5f7-eb20-44aa-98ae-ab067a7d7115',
   'MR-021', 'เอ สีดอน', NULL, NULL, '1329900377473',
   'staff', 'regular_salary', 'active',
   '420626ba-9679-45a9-a6af-8440ac908a07',
   'a3034aa4-bb08-422c-8d49-36d88d242f56',
   0, '2014-10-21', NULL, NULL, NULL, false),

  ('c514f006-0ca2-45b9-9fb7-93721dc427e1',
   'MR-022', 'รวีโรจน์ ใจงาม', NULL, NULL, '1329900731111',
   'staff', 'regular_salary', 'active',
   '420626ba-9679-45a9-a6af-8440ac908a07',
   'a3034aa4-bb08-422c-8d49-36d88d242f56',
   0, '2014-10-21', NULL, NULL, NULL, false);

-- Staff HQ-01
INSERT INTO employees (id, employee_code, full_name_th, full_name_en, nickname, tax_id,
  role, employment_type, employment_status, cost_center_id, supervisor_id,
  salary_base, hire_date, bank_name, bank_account, phone, is_attendance_exempt)
VALUES
  ('e240c582-51ae-429d-abc9-26535734fec0',
   'MR-023', 'ศศินาพร สุดเอี่ยม', 'Sasinaporn Sudaiam', 'ปิง', '1320100233657',
   'staff', 'regular_salary', 'active',
   'e257f721-a065-46d5-ae9d-29bb98fcb1dd',
   'bc049c43-bf92-4fac-8e15-4c64fbdb75a2',
   10530, '2022-08-01', 'SCB', '899-2-63561-8', '935913312', false),

  ('ae8e056a-8246-4120-86cb-cebb2e6ebb3e',
   'MR-024', 'ขวัญหทัย กระสันดี', 'Kwanrathai Krasandee', 'พิ้ง', '1329901112708',
   'staff', 'regular_salary', 'active',
   'e257f721-a065-46d5-ae9d-29bb98fcb1dd',
   'bc049c43-bf92-4fac-8e15-4c64fbdb75a2',
   10530, '2025-07-01', 'SCB', '899-2-80133-2', '963819867', false);

-- Staff CC-04
INSERT INTO employees (id, employee_code, full_name_th, full_name_en, nickname, tax_id,
  role, employment_type, employment_status, cost_center_id, supervisor_id,
  salary_base, hire_date, bank_name, bank_account, phone, is_attendance_exempt)
VALUES
  ('b57225c5-4b04-4d5d-8772-dfab6c554438',
   'MR-025', 'ทิพย์วิมล สติมั่น', NULL, NULL, '1329900301876',
   'staff', 'regular_salary', 'active',
   '5094ff92-85f6-4262-8701-b3fc11b6d2ec',
   'cf158463-0549-40eb-8929-732b67e18f07',
   0, '2014-10-21', NULL, NULL, NULL, false),

  ('b072a02b-fea9-4657-89eb-e96095e9449f',
   'MR-026', 'สุธิตา ลาภเหลือ', NULL, NULL, '1321300091237',
   'staff', 'regular_salary', 'active',
   '5094ff92-85f6-4262-8701-b3fc11b6d2ec',
   'cf158463-0549-40eb-8929-732b67e18f07',
   0, '2014-10-21', NULL, NULL, NULL, false);

-- Support Staff
INSERT INTO employees (id, employee_code, full_name_th, full_name_en, nickname, tax_id,
  role, employment_type, employment_status, cost_center_id, supervisor_id,
  salary_base, hire_date, bank_name, bank_account, phone, is_attendance_exempt)
VALUES
  ('3786ab49-cffd-4a5b-a49f-be2b1e8c3544',
   'MR-027', 'ลัดดา สติภา', NULL, NULL, '1320100093057',
   'staff', 'regular_salary', 'active',
   'd3b64365-f632-4009-9b73-16324cf70398',
   '77ff2b09-34ab-4e3f-9640-373e761cd761',
   0, '2014-10-21', NULL, NULL, NULL, false),

  ('39910984-cd13-48f6-9c44-e9031a6d342b',
   'MR-028', 'นนทวัฒน์ บุญปลั่ง', NULL, NULL, '1103701937882',
   'staff', 'regular_salary', 'active',
   '236a2da0-9995-4182-a394-a009fa5d4bbd',
   '77ff2b09-34ab-4e3f-9640-373e761cd761',
   0, '2014-10-21', NULL, NULL, NULL, false);

-- SSO Only
INSERT INTO employees (id, employee_code, full_name_th, full_name_en, nickname, tax_id,
  role, employment_type, employment_status, cost_center_id, supervisor_id,
  salary_base, hire_date, bank_name, bank_account, phone, is_attendance_exempt)
VALUES
  ('32288115-c364-45c1-8c2a-1e3f1deaa777',
   'MR-029', 'สังวาลย์ หาญเหี้ยม', NULL, NULL, '3320100252020',
   'staff', 'regular_salary', 'active',
   '661224c5-0da8-4265-8e53-2600b3723c25',
   '77ff2b09-34ab-4e3f-9640-373e761cd761',
   0, '2019-01-01', NULL, NULL, NULL, false);

-- PC Staff
INSERT INTO employees (id, employee_code, full_name_th, full_name_en, nickname, tax_id,
  role, employment_type, employment_status, cost_center_id, supervisor_id,
  salary_base, hire_date, bank_name, bank_account, phone, is_attendance_exempt)
VALUES
  ('bb73343d-9fdf-49c2-994e-5f139e412eec',
   'MR-030', 'กัญญาวีร์ สุราช', NULL, NULL, '1329900727733',
   'pc_staff', 'regular_salary', 'active',
   'fe136849-5c0d-4772-aff3-04b7c8851d47',
   '77ff2b09-34ab-4e3f-9640-373e761cd761',
   0, '2014-10-21', NULL, NULL, NULL, false),

  ('a0a824ae-9bdd-469f-adb5-f72fe38d5c74',
   'MR-031', 'เมตตา แฝงทรัพย์', NULL, NULL, '1739990100341',
   'pc_staff', 'regular_salary', 'active',
   'fe136849-5c0d-4772-aff3-04b7c8851d47',
   '77ff2b09-34ab-4e3f-9640-373e761cd761',
   0, '2014-10-21', NULL, NULL, NULL, false),

  ('e7f88e17-5805-489a-87b8-9b78f10be1d4',
   'MR-032', 'เต็มตรอง พิจารณ์', NULL, NULL, '1329901166875',
   'pc_staff', 'regular_salary', 'active',
   'fe136849-5c0d-4772-aff3-04b7c8851d47',
   '77ff2b09-34ab-4e3f-9640-373e761cd761',
   0, '2014-10-21', NULL, NULL, NULL, false);