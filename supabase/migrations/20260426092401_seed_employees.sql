-- Seed Employees (32 คน)
-- Directors/Delegates (3 คน)
INSERT INTO employees (
  employee_code, full_name_th, nickname,
  role, employment_type, employment_status,
  cost_center_id, salary_base, hire_date
) VALUES
  (
    NULL, 'อมร', 'เฮีย',
    'owner', 'director_salary', 'active',
    (SELECT id FROM cost_centers WHERE code = 'CC-HQ-WS'),
    20000, '2014-10-21'
  ),
  (
    NULL, 'ไนซ์', 'ไนซ์',
    'owner_delegate', 'director_salary', 'active',
    (SELECT id FROM cost_centers WHERE code = 'CC-HQ-WS'),
    20000, '2014-10-21'
  ),
  (
    'CEO02', 'ศศิ เกียรติคุณรัตน์', 'จิว',
    'owner_delegate', 'director_salary', 'active',
    (SELECT id FROM cost_centers WHERE code = 'CC-HQ-WS'),
    30000, '2014-10-21'
  );

-- Supervisors (5 คน)
INSERT INTO employees (
  employee_code, full_name_th, nickname,
  role, employment_type, employment_status,
  cost_center_id, salary_base, hire_date
) VALUES
  (
    'MY04', 'ศิริรัตน์ ผิวขาว', 'ติ๋ง',
    'supervisor', 'regular_salary', 'active',
    (SELECT id FROM cost_centers WHERE code = 'CC-SUPPORT-WH'),
    12444, '2014-10-21'
  ),
  (
    'MY05', 'ภัทราภรณ์ ปัสสาวะกัง', 'เมล์',
    'supervisor', 'regular_salary', 'active',
    (SELECT id FROM cost_centers WHERE code = 'CC-HQ-WS'),
    10820, '2014-10-21'
  ),
  (
    'MY11', 'ศิราพร สิทธิรัมย์', 'จอย',
    'supervisor', 'regular_salary', 'active',
    (SELECT id FROM cost_centers WHERE code = 'CC-04'),
    34000, '2014-10-21'
  ),
  (
    'MY14', 'กษิดิศ สงึมรัมย์', 'ค๊อป',
    'supervisor', 'regular_salary', 'active',
    (SELECT id FROM cost_centers WHERE code = 'CC-01'),
    31000, '2014-10-21'
  ),
  (
    'MY23', 'ดวงหทัย ปวนใต้', 'เดือน',
    'supervisor', 'regular_salary', 'active',
    (SELECT id FROM cost_centers WHERE code = 'CC-HQ-WS'),
    16200, '2014-10-21'
  );

-- Staff CC-HQ-WS (6 คน)
INSERT INTO employees (
  employee_code, full_name_th, nickname,
  role, employment_type, employment_status,
  cost_center_id, salary_base, hire_date
) VALUES
  (
    'MY06', 'ปรเมศร์ มีทอง', 'น็อต',
    'staff', 'regular_salary', 'active',
    (SELECT id FROM cost_centers WHERE code = 'CC-HQ-WS'),
    10600, '2014-10-21'
  ),
  (
    'MY08', 'สุวิมล แสงสุข', 'อุ้ม',
    'staff', 'regular_salary', 'active',
    (SELECT id FROM cost_centers WHERE code = 'CC-HQ-WS'),
    10530, '2014-10-21'
  ),
  (
    'MY10', 'พนัสโชค มีทองแสน', 'เยียร์',
    'staff', 'regular_salary', 'active',
    (SELECT id FROM cost_centers WHERE code = 'CC-HQ-WS'),
    10530, '2014-10-21'
  ),
  (
    'MY17', 'ณัฐรียา พิมพ์สวัสดิ์', 'เค้ก',
    'staff', 'regular_salary', 'active',
    (SELECT id FROM cost_centers WHERE code = 'CC-HQ-WS'),
    10530, '2014-10-21'
  ),
  (
    'MY19', 'อรรถพล คำเบ้า', 'ต้อม',
    'staff', 'regular_salary', 'active',
    (SELECT id FROM cost_centers WHERE code = 'CC-HQ-WS'),
    10530, '2014-10-21'
  ),
  (
    'MY22', 'ศริพงศ์ ทองแดง', 'เป็ด',
    'staff', 'regular_salary', 'active',
    (SELECT id FROM cost_centers WHERE code = 'CC-HQ-WS'),
    12000, '2014-10-21'
  );

-- Staff CC-01 (2 คน)
INSERT INTO employees (
  employee_code, full_name_th, nickname,
  role, employment_type, employment_status,
  cost_center_id, salary_base, hire_date
) VALUES
  (
    'MY15', 'ศศินาพร สุดเอี่ยม', 'ปิง',
    'staff', 'regular_salary', 'active',
    (SELECT id FROM cost_centers WHERE code = 'CC-01'),
    10530, '2014-10-21'
  ),
  (
    'MY24', 'ขวัญหทัย กระสันดี', 'พิ้ง',
    'staff', 'regular_salary', 'active',
    (SELECT id FROM cost_centers WHERE code = 'CC-01'),
    10530, '2014-10-21'
  );

-- Staff CC-04 (2 คน)
INSERT INTO employees (
  employee_code, full_name_th, nickname,
  role, employment_type, employment_status,
  cost_center_id, salary_base, hire_date
) VALUES
  (
    'MY12', 'ทิพย์วิมล สติมั่น', 'ขิง',
    'staff', 'regular_salary', 'active',
    (SELECT id FROM cost_centers WHERE code = 'CC-04'),
    10530, '2014-10-21'
  ),
  (
    'MY26', 'สุธิตา ลาภเหลือ', 'หน่อย',
    'staff', 'regular_salary', 'active',
    (SELECT id FROM cost_centers WHERE code = 'CC-04'),
    15000, '2014-10-21'
  );

-- Staff CC-SUPPORT-HR (1 คน)
INSERT INTO employees (
  employee_code, full_name_th, nickname,
  role, employment_type, employment_status,
  cost_center_id, salary_base, hire_date
) VALUES
  (
    'MY07', 'เกวลี สุระวิทย์', 'การ์ตูน',
    'hr_admin', 'regular_salary', 'active',
    (SELECT id FROM cost_centers WHERE code = 'CC-SUPPORT-HR'),
    15453, '2014-10-21'
  );

-- Staff CC-SUPPORT-FIN (3 คน)
INSERT INTO employees (
  employee_code, full_name_th, nickname,
  role, employment_type, employment_status,
  cost_center_id, salary_base, hire_date
) VALUES
  (
    'MY02', 'รัตนาวดี มั่นหมาย', 'ก้อย',
    'finance', 'regular_salary', 'active',
    (SELECT id FROM cost_centers WHERE code = 'CC-SUPPORT-FIN'),
    14484, '2014-10-21'
  ),
  (
    'MY16', 'พรนภา โนนสาลี', 'นา',
    'finance', 'regular_salary', 'active',
    (SELECT id FROM cost_centers WHERE code = 'CC-SUPPORT-FIN'),
    10530, '2014-10-21'
  ),
  (
    'MY21', 'ลัดดา สติภา', 'แอ๊ด',
    'finance', 'regular_salary', 'active',
    (SELECT id FROM cost_centers WHERE code = 'CC-SUPPORT-FIN'),
    10530, '2014-10-21'
  );

-- Staff CC-SUPPORT-IT (1 คน)
INSERT INTO employees (
  employee_code, full_name_th, nickname,
  role, employment_type, employment_status,
  cost_center_id, salary_base, hire_date
) VALUES
  (
    'MY25', 'นนทวัฒน์ บุญปลั่ง', 'บอส',
    'it_support', 'regular_salary', 'active',
    (SELECT id FROM cost_centers WHERE code = 'CC-SUPPORT-IT'),
    12500, '2014-10-21'
  );

-- Staff CC-SUPPORT-WH (5 คน)
INSERT INTO employees (
  employee_code, full_name_th, nickname,
  role, employment_type, employment_status,
  cost_center_id, salary_base, hire_date
) VALUES
  (
    'MY01', 'สุจิตรา ทรายทอง', 'ตา',
    'staff', 'regular_salary', 'active',
    (SELECT id FROM cost_centers WHERE code = 'CC-SUPPORT-WH'),
    14280, '2014-10-21'
  ),
  (
    'MY09', 'สุนัย เลือดขุนทด', 'ปู',
    'staff', 'regular_salary', 'active',
    (SELECT id FROM cost_centers WHERE code = 'CC-SUPPORT-WH'),
    10530, '2014-10-21'
  ),
  (
    'MY13', 'ธนภัทร ขอชนะ', 'นัด',
    'staff', 'regular_salary', 'active',
    (SELECT id FROM cost_centers WHERE code = 'CC-SUPPORT-WH'),
    10530, '2014-10-21'
  ),
  (
    'MY18', 'เอ สีดอน', 'ต้อม (เอ)',
    'staff', 'regular_salary', 'active',
    (SELECT id FROM cost_centers WHERE code = 'CC-SUPPORT-WH'),
    10530, '2014-10-21'
  ),
  (
    'MY20', 'รวีโรจน์ ใจงาม', 'ไอซ์',
    'staff', 'regular_salary', 'active',
    (SELECT id FROM cost_centers WHERE code = 'CC-SUPPORT-WH'),
    10530, '2014-10-21'
  );

-- SSO Only (1 คน)
INSERT INTO employees (
  employee_code, full_name_th, nickname,
  role, employment_type, employment_status,
  cost_center_id, salary_base, hire_date
) VALUES
  (
    NULL, 'สังวาลย์ หาญเหี้ยม', 'สังวาลย์',
    'staff', 'regular_salary', 'active_no_payroll',
    (SELECT id FROM cost_centers WHERE code = 'CC-SUPPORT-WH'),
    0, '2019-01-01'
  );

-- PC (3 คน)
INSERT INTO employees (
  employee_code, full_name_th, nickname,
  role, employment_type, employment_status,
  cost_center_id, salary_base, hire_date,
  pc_sponsor
) VALUES
  (
    'PC01', 'กัญญาวีร์ สุราช', 'ชมพู่',
    'pc_staff', 'regular_salary', 'active',
    (SELECT id FROM cost_centers WHERE code = 'CC-01'),
    0, '2021-03-15', 'NBD'
  ),
  (
    'PC02', 'เมตตา แฝงทรัพย์', 'ต่าย',
    'pc_staff', 'regular_salary', 'active',
    (SELECT id FROM cost_centers WHERE code = 'CC-01'),
    0, '2025-10-01', 'Blackmores'
  ),
  (
    'PC03', 'เต็มตรอง พิจารณ์', 'พลอย',
    'pc_staff', 'regular_salary', 'active',
    (SELECT id FROM cost_centers WHERE code = 'CC-01'),
    0, '2026-04-20', 'Wellgate'
  );

-- Update supervisor_id
UPDATE employees SET supervisor_id = (SELECT id FROM employees WHERE employee_code = 'MY04')
  WHERE employee_code IN ('MY01', 'MY09', 'MY13', 'MY18', 'MY20');

UPDATE employees SET supervisor_id = (SELECT id FROM employees WHERE employee_code = 'MY05')
  WHERE employee_code IN ('MY06', 'MY08', 'MY10', 'MY17', 'MY19', 'MY22');

UPDATE employees SET supervisor_id = (SELECT id FROM employees WHERE employee_code = 'MY14')
  WHERE employee_code IN ('MY15', 'MY24', 'PC01', 'PC02', 'PC03');

UPDATE employees SET supervisor_id = (SELECT id FROM employees WHERE employee_code = 'MY11')
  WHERE employee_code IN ('MY12', 'MY26');

-- Pharmacist licenses
UPDATE employees SET
  pharmacist_license = 'TBD',
  pharmacist_license_expiry = NULL
WHERE employee_code IN ('MY11', 'MY14');