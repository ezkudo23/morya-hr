-- Patch: leave_requests — เพิ่ม columns ที่ขาดจาก MRD
-- Migration: patch_leave_requests
-- Date: 27 เม.ย. 2569

ALTER TABLE leave_requests
  -- Backdate flag (ลาป่วยเท่านั้น, window ≤ 3 วัน)
  ADD COLUMN is_backdate BOOLEAN NOT NULL DEFAULT false,

  -- Approval step ปัจจุบัน
  -- 1 = รอ Supervisor
  -- 2 = รอ HR Admin (ลา 4-7 วัน)
  -- 3 = รอ Owner (ลา 8+ วัน)
  ADD COLUMN approval_step INTEGER NOT NULL DEFAULT 1
    CHECK (approval_step IN (1, 2, 3)),

  -- จำนวนวันลาที่ request (ใช้ตรวจ routing)
  -- ≤3 วัน → step max = 1
  -- 4-7 วัน → step max = 2
  -- 8+ วัน → step max = 3
  ADD COLUMN approval_step_max INTEGER NOT NULL DEFAULT 1
    CHECK (approval_step_max IN (1, 2, 3)),

  -- Flag ว่าต้องตรวจ diligence หรือไม่
  -- sick = true → ถ้า approve แล้ว trigger ตัดเบี้ยขยันใน employee_diligence_counters
  ADD COLUMN triggers_diligence_check BOOLEAN NOT NULL DEFAULT false,

  -- Probation guard
  -- ถ้า true = พนักงานยังอยู่ในช่วงทดลองงาน ณ วันที่ submit
  -- ใช้ block ลากิจ (personal) → redirect เป็น LWP
  ADD COLUMN is_probation BOOLEAN NOT NULL DEFAULT false,

  -- Advance notice validation result
  -- true = แจ้งล่วงหน้าตามกำหนด | false = ไม่ถึง → trigger ตัดเบี้ยขยัน
  ADD COLUMN advance_notice_met BOOLEAN NOT NULL DEFAULT true;

-- Comment อธิบาย business rules
COMMENT ON COLUMN leave_requests.is_backdate IS
  'ลาป่วยย้อนหลัง — window ≤ 3 วัน, ต้องมี attachment_url';

COMMENT ON COLUMN leave_requests.approval_step IS
  'step ปัจจุบัน: 1=Supervisor, 2=HR Admin, 3=Owner';

COMMENT ON COLUMN leave_requests.approval_step_max IS
  'step สูงสุดที่ต้องผ่าน — คำนวณจาก days: ≤3→1, 4-7→2, 8+→3';

COMMENT ON COLUMN leave_requests.triggers_diligence_check IS
  'true เมื่อ leave_type=sick — approve แล้ว increment sick_leave_count ใน diligence_counters (D16)';

COMMENT ON COLUMN leave_requests.is_probation IS
  'true = ทดลองงาน ณ วัน submit — block personal leave (redirect LWP)';

COMMENT ON COLUMN leave_requests.advance_notice_met IS
  'false = ไม่แจ้งล่วงหน้าตามกำหนด (annual=7วัน, อื่นๆ=3วัน) → trigger ตัดเบี้ยขยัน';