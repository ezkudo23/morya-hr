-- Function: approve_leave_request
-- หน้าที่: Supervisor/HR Admin/Owner approve leave — advance step หรือ final approve
-- Security: SECURITY DEFINER (bypass RLS)
-- Date: 27 เม.ย. 2569

CREATE OR REPLACE FUNCTION approve_leave_request(
  p_leave_request_id  UUID,
  p_approver_id       UUID,     -- auth.users.id ของคนที่ approve
  p_action            TEXT,     -- 'approve' | 'reject'
  p_note              TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_leave         RECORD;
  v_approver      RECORD;
  v_expected_role TEXT;
  v_next_approver_id UUID;
  v_current_year  INTEGER := EXTRACT(YEAR FROM CURRENT_DATE);
  v_chain_entry   JSONB;
BEGIN

  -- ────────────────────────────────────────────
  -- 1. ดึง leave_request
  -- ────────────────────────────────────────────
  SELECT lr.*, e.supervisor_id
  INTO v_leave
  FROM leave_requests lr
  JOIN employees e ON e.id = lr.employee_id
  WHERE lr.id = p_leave_request_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'LEAVE_REQUEST_NOT_FOUND');
  END IF;

  -- ต้องยัง pending อยู่
  IF v_leave.status != 'pending' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'ALREADY_PROCESSED',
      'status', v_leave.status
    );
  END IF;

  -- ────────────────────────────────────────────
  -- 2. ดึงข้อมูล approver
  -- ────────────────────────────────────────────
  SELECT p.role, p.employee_id
  INTO v_approver
  FROM profiles p
  WHERE p.id = p_approver_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'APPROVER_NOT_FOUND');
  END IF;

  -- ────────────────────────────────────────────
  -- 3. Validate approver role ตาม step
  -- ────────────────────────────────────────────
  CASE v_leave.approval_step
    WHEN 1 THEN v_expected_role := 'supervisor';
    WHEN 2 THEN v_expected_role := 'hr_admin';
    WHEN 3 THEN v_expected_role := 'owner';
    ELSE
      RETURN jsonb_build_object('success', false, 'error', 'INVALID_APPROVAL_STEP');
  END CASE;

  -- Owner/Delegate สามารถ approve ได้ทุก step
  IF v_approver.role NOT IN ('owner', 'owner_delegate')
     AND v_approver.role != v_expected_role THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'UNAUTHORIZED_APPROVER',
      'expected_role', v_expected_role,
      'actual_role', v_approver.role
    );
  END IF;

  -- ตรวจว่าเป็น current_approver ที่ถูกต้อง
  IF v_leave.current_approver_id != p_approver_id
     AND v_approver.role NOT IN ('owner', 'owner_delegate') THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_CURRENT_APPROVER');
  END IF;

  -- ────────────────────────────────────────────
  -- 4. Build chain entry
  -- ────────────────────────────────────────────
  v_chain_entry := jsonb_build_object(
    'step',        v_leave.approval_step,
    'role',        v_approver.role,
    'approver_id', p_approver_id,
    'action',      p_action,
    'note',        p_note,
    'at',          NOW()
  );

  -- ────────────────────────────────────────────
  -- 5. REJECT
  -- ────────────────────────────────────────────
  IF p_action = 'reject' THEN
    UPDATE leave_requests SET
      status           = 'rejected',
      approver_chain   = approver_chain || v_chain_entry,
      approver_note    = p_note,
      rejected_at      = NOW(),
      updated_at       = NOW()
    WHERE id = p_leave_request_id;

    RETURN jsonb_build_object(
      'success', true,
      'action',  'rejected',
      'leave_request_id', p_leave_request_id
    );
  END IF;

  -- ────────────────────────────────────────────
  -- 6. APPROVE — ตรวจว่าถึง step สุดท้ายหรือยัง
  -- ────────────────────────────────────────────
  IF v_leave.approval_step < v_leave.approval_step_max THEN

    -- ยังไม่ถึง step สุดท้าย → advance step
    -- หา approver ของ step ถัดไป
    CASE (v_leave.approval_step + 1)
      WHEN 2 THEN
        -- หา HR Admin
        SELECT p.id INTO v_next_approver_id
        FROM profiles p
        WHERE p.role = 'hr_admin' AND p.is_active = true
        LIMIT 1;
      WHEN 3 THEN
        -- หา Owner
        SELECT p.id INTO v_next_approver_id
        FROM profiles p
        WHERE p.role = 'owner' AND p.is_active = true
        LIMIT 1;
      ELSE
        v_next_approver_id := NULL;
    END CASE;

    UPDATE leave_requests SET
      approval_step      = approval_step + 1,
      approver_chain     = approver_chain || v_chain_entry,
      current_approver_id = v_next_approver_id,
      updated_at         = NOW()
    WHERE id = p_leave_request_id;

    RETURN jsonb_build_object(
      'success',          true,
      'action',           'advanced',
      'next_step',        v_leave.approval_step + 1,
      'next_approver_id', v_next_approver_id,
      'leave_request_id', p_leave_request_id
    );

  ELSE

    -- ────────────────────────────────────────────
    -- 7. FINAL APPROVE
    -- ────────────────────────────────────────────

    -- 7a. Final approve leave_request
    UPDATE leave_requests SET
      status              = 'approved',
      approver_chain      = approver_chain || v_chain_entry,
      approver_note       = p_note,
      approved_at         = NOW(),
      current_approver_id = NULL,
      updated_at          = NOW()
    WHERE id = p_leave_request_id;

    -- 7b. Deduct leave_balances (ยกเว้น military)
    IF v_leave.leave_type != 'military' THEN
      UPDATE leave_balances SET
        used_days  = used_days + v_leave.days,
        updated_at = NOW()
      WHERE employee_id = v_leave.employee_id
        AND year        = v_current_year
        AND leave_type  = v_leave.leave_type;
    END IF;

    -- 7c. Diligence: ลาป่วย → increment sick_leave_count (D16)
    IF v_leave.triggers_diligence_check THEN
      INSERT INTO employee_diligence_counters (
        employee_id, year, month,
        sick_leave_count,
        late_count, forgot_count, correction_count,
        is_forfeited
      )
      VALUES (
        v_leave.employee_id,
        EXTRACT(YEAR FROM v_leave.start_date),
        EXTRACT(MONTH FROM v_leave.start_date),
        1, 0, 0, 0, false
      )
      ON CONFLICT (employee_id, year, month) DO UPDATE SET
        sick_leave_count = employee_diligence_counters.sick_leave_count + 1,
        -- ลาป่วย ≥ 1 ครั้ง → ตัดเบี้ยขยันทันที (D16/C-03)
        is_forfeited = true,
        forfeited_reason = COALESCE(
          employee_diligence_counters.forfeited_reason,
          'sick_leave'
        ),
        updated_at = NOW();
    END IF;

    -- 7d. Advance notice ไม่ครบ → increment counter (C-04)
    IF NOT v_leave.advance_notice_met THEN
      INSERT INTO employee_diligence_counters (
        employee_id, year, month,
        sick_leave_count,
        late_count, forgot_count, correction_count,
        is_forfeited
      )
      VALUES (
        v_leave.employee_id,
        EXTRACT(YEAR FROM v_leave.start_date),
        EXTRACT(MONTH FROM v_leave.start_date),
        0, 0, 0, 1, false   -- นับเป็น correction_count
      )
      ON CONFLICT (employee_id, year, month) DO UPDATE SET
        correction_count = employee_diligence_counters.correction_count + 1,
        -- ถ้า total (late + forgot + correction) ≥ 3 → ตัด (C-04)
        is_forfeited = CASE
          WHEN (
            employee_diligence_counters.late_count +
            employee_diligence_counters.forgot_count +
            employee_diligence_counters.correction_count + 1
          ) >= 3 THEN true
          ELSE employee_diligence_counters.is_forfeited
        END,
        forfeited_reason = CASE
          WHEN (
            employee_diligence_counters.late_count +
            employee_diligence_counters.forgot_count +
            employee_diligence_counters.correction_count + 1
          ) >= 3 THEN COALESCE(
            employee_diligence_counters.forfeited_reason,
            'late_forgot_correction_threshold'
          )
          ELSE employee_diligence_counters.forfeited_reason
        END,
        updated_at = NOW();
    END IF;

    RETURN jsonb_build_object(
      'success',          true,
      'action',           'final_approved',
      'leave_request_id', p_leave_request_id,
      'days_deducted',    v_leave.days,
      'leave_type',       v_leave.leave_type,
      'diligence_updated', v_leave.triggers_diligence_check OR NOT v_leave.advance_notice_met
    );

  END IF;

EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'success', false,
      'error',   'UNEXPECTED_ERROR',
      'detail',  SQLERRM
    );
END;
$$;

-- Grant execute
GRANT EXECUTE ON FUNCTION approve_leave_request TO authenticated;