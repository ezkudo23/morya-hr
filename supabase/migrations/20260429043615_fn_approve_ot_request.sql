-- Function: approve_ot_request
-- หน้าที่: Supervisor/Owner approve OT — advance step หรือ final approve
-- Security: SECURITY DEFINER (bypass RLS)
-- Date: 29 เม.ย. 2569

CREATE OR REPLACE FUNCTION approve_ot_request(
  p_ot_request_id UUID,
  p_approver_id   UUID,
  p_action        TEXT,     -- 'approve' | 'reject'
  p_note          TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ot            RECORD;
  v_approver      RECORD;
  v_next_approver_id UUID;
  v_chain_entry   JSONB;
BEGIN

  -- ────────────────────────────────────────────
  -- 1. ดึง ot_request
  -- ────────────────────────────────────────────
  SELECT * INTO v_ot
  FROM ot_requests
  WHERE id = p_ot_request_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'OT_REQUEST_NOT_FOUND');
  END IF;

  IF v_ot.status != 'pending' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error',   'ALREADY_PROCESSED',
      'status',  v_ot.status
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
  -- 3. Validate approver
  -- Owner/Delegate approve ได้ทุก step
  -- ────────────────────────────────────────────
  IF v_approver.role NOT IN ('owner', 'owner_delegate') THEN
    IF v_ot.current_approver_id != p_approver_id THEN
      RETURN jsonb_build_object('success', false, 'error', 'NOT_CURRENT_APPROVER');
    END IF;
  END IF;

  -- ────────────────────────────────────────────
  -- 4. Build chain entry
  -- ────────────────────────────────────────────
  v_chain_entry := jsonb_build_object(
    'step',        v_ot.approval_step,
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
    UPDATE ot_requests SET
      status           = 'rejected',
      approver_chain   = approver_chain || v_chain_entry,
      approver_note    = p_note,
      rejected_at      = NOW(),
      updated_at       = NOW()
    WHERE id = p_ot_request_id;

    RETURN jsonb_build_object(
      'success',        true,
      'action',         'rejected',
      'ot_request_id',  p_ot_request_id
    );
  END IF;

  -- ────────────────────────────────────────────
  -- 6. APPROVE — advance step หรือ final
  -- ────────────────────────────────────────────
  IF v_ot.approval_step < v_ot.approval_step_max THEN

    -- ยังไม่ถึง step สุดท้าย → หา Owner
    SELECT p.id INTO v_next_approver_id
    FROM profiles p
    WHERE p.role IN ('owner', 'owner_delegate')
      AND p.is_active = true
    ORDER BY p.role ASC
    LIMIT 1;

    UPDATE ot_requests SET
      approval_step       = approval_step + 1,
      approver_chain      = approver_chain || v_chain_entry,
      current_approver_id = v_next_approver_id,
      updated_at          = NOW()
    WHERE id = p_ot_request_id;

    RETURN jsonb_build_object(
      'success',          true,
      'action',           'advanced',
      'next_step',        v_ot.approval_step + 1,
      'next_approver_id', v_next_approver_id,
      'ot_request_id',    p_ot_request_id
    );

  ELSE

    -- Final approve
    UPDATE ot_requests SET
      status              = 'approved',
      approver_chain      = approver_chain || v_chain_entry,
      approver_note       = p_note,
      approved_at         = NOW(),
      current_approver_id = NULL,
      updated_at          = NOW()
    WHERE id = p_ot_request_id;

    RETURN jsonb_build_object(
      'success',        true,
      'action',         'final_approved',
      'ot_request_id',  p_ot_request_id,
      'hours',          v_ot.hours
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

GRANT EXECUTE ON FUNCTION approve_ot_request TO authenticated;