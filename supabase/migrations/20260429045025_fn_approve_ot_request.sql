-- Function: approve_ot_request
-- หน้าที่: Supervisor approve/reject OT + บันทึก audit chain
-- Security: SECURITY DEFINER (bypass RLS)
-- Date: 29 เม.ย. 2569

CREATE OR REPLACE FUNCTION approve_ot_request(
  p_ot_request_id  UUID,
  p_approver_id    UUID,
  p_action         TEXT,     -- 'approve' | 'reject'
  p_note           TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ot          RECORD;
  v_approver    RECORD;
  v_chain_entry JSONB;
BEGIN

  -- ────────────────────────────────────────────
  -- 1. ดึง ot_request
  -- ────────────────────────────────────────────
  SELECT ot.*, e.supervisor_id
  INTO v_ot
  FROM ot_requests ot
  JOIN employees e ON e.id = ot.employee_id
  WHERE ot.id = p_ot_request_id;

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
  -- 2. ดึง approver role
  -- ────────────────────────────────────────────
  SELECT p.role, p.employee_id
  INTO v_approver
  FROM profiles p
  WHERE p.id = p_approver_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'APPROVER_NOT_FOUND');
  END IF;

  -- ────────────────────────────────────────────
  -- 3. ตรวจสิทธิ์ — OT มีแค่ 1 step (Supervisor เท่านั้น)
  -- ────────────────────────────────────────────
  IF v_approver.role NOT IN ('supervisor', 'owner', 'owner_delegate', 'hr_admin') THEN
    RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  -- Supervisor ต้องเป็น supervisor ของ employee นั้น
  IF v_approver.role = 'supervisor' THEN
    IF v_approver.employee_id != v_ot.supervisor_id THEN
      RETURN jsonb_build_object('success', false, 'error', 'NOT_YOUR_TEAM');
    END IF;
  END IF;

  -- ────────────────────────────────────────────
  -- 4. Build audit chain entry
  -- ────────────────────────────────────────────
  v_chain_entry := jsonb_build_object(
    'approver_id',   p_approver_id,
    'role',          v_approver.role,
    'action',        p_action,
    'note',          p_note,
    'acted_at',      NOW()
  );

  -- ────────────────────────────────────────────
  -- 5. Reject
  -- ────────────────────────────────────────────
  IF p_action = 'reject' THEN
    UPDATE ot_requests SET
      status              = 'rejected',
      approver_chain      = approver_chain || v_chain_entry,
      approver_note       = p_note,
      rejected_at         = NOW(),
      current_approver_id = NULL,
      updated_at          = NOW()
    WHERE id = p_ot_request_id;

    RETURN jsonb_build_object(
      'success',        true,
      'action',         'rejected',
      'ot_request_id',  p_ot_request_id
    );
  END IF;

  -- ────────────────────────────────────────────
  -- 6. Approve — final (OT มีแค่ 1 step)
  -- ────────────────────────────────────────────
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
    'ot_hours',       v_ot.ot_hours,
    'ot_type',        v_ot.ot_type,
    'rate_multiplier', v_ot.rate_multiplier
  );

EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'success', false,
      'error',   'UNEXPECTED_ERROR',
      'detail',  SQLERRM
    );
END;
$$;

GRANT EXECUTE ON FUNCTION approve_ot_request(UUID, UUID, TEXT, TEXT) TO authenticated;