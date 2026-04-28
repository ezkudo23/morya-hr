// components/leave/leave-history-list.tsx
// หน้าที่: Staff ดูประวัติคำขอลาของตัวเอง

'use client'

import { useState, useEffect, useCallback } from 'react'
import { createClient } from '@/lib/supabase/client'
import { LEAVE_TYPE_LABELS, LeaveType } from '@/hooks/use-leave'

interface LeaveHistoryItem {
  id:                string
  leave_type:        LeaveType
  start_date:        string
  end_date:          string
  days:              number
  is_half_day:       boolean
  half_day_period:   'morning' | 'afternoon' | null
  reason:            string | null
  status:            'pending' | 'approved' | 'rejected' | 'cancelled'
  is_backdate:       boolean
  approval_step:     number
  approval_step_max: number
  approver_note:     string | null
  approved_at:       string | null
  rejected_at:       string | null
  created_at:        string
}

interface LeaveHistoryListProps {
  employeeId: string
}

const STATUS_CONFIG = {
  pending:   { label: 'รออนุมัติ', bg: 'bg-amber-50',  text: 'text-amber-600',  dot: 'bg-amber-400'  },
  approved:  { label: 'อนุมัติแล้ว', bg: 'bg-green-50', text: 'text-green-600',  dot: 'bg-green-400'  },
  rejected:  { label: 'ไม่อนุมัติ', bg: 'bg-red-50',   text: 'text-red-600',    dot: 'bg-red-400'    },
  cancelled: { label: 'ยกเลิก',     bg: 'bg-gray-50',  text: 'text-gray-400',   dot: 'bg-gray-300'   },
}

export function LeaveHistoryList({ employeeId }: LeaveHistoryListProps) {
  const supabase = createClient()

  const currentYear = new Date().getFullYear()
  const [year,    setYear]    = useState(currentYear)
  const [history, setHistory] = useState<LeaveHistoryItem[]>([])
  const [total,   setTotal]   = useState(0)
  const [loading, setLoading] = useState(true)

  const toThaiDate = (dateStr: string) =>
    new Date(dateStr).toLocaleDateString('th-TH', {
      year: 'numeric', month: 'short', day: 'numeric',
    })

  const fetchHistory = useCallback(async () => {
    setLoading(true)
    try {
      const { data, error } = await supabase.rpc('get_leave_history', {
        p_employee_id: employeeId,
        p_year:        year,
        p_limit:       50,
        p_offset:      0,
      })
      if (error) throw error
      if (data?.success) {
        setHistory(data.history ?? [])
        setTotal(data.total ?? 0)
      }
    } catch (err) {
      console.error(err)
    } finally {
      setLoading(false)
    }
  }, [employeeId, year, supabase])

  useEffect(() => {
    fetchHistory()
  }, [fetchHistory])

  if (loading) {
    return (
      <div className="space-y-3">
        {Array.from({ length: 3 }).map((_, i) => (
          <div key={i} className="h-20 rounded-xl bg-gray-100 animate-pulse" />
        ))}
      </div>
    )
  }

  return (
    <div className="space-y-4">

      {/* Year selector */}
      <div className="flex items-center justify-between">
        <p className="text-xs text-gray-400">
          {total > 0 ? `${total} รายการ` : 'ไม่มีประวัติ'}
        </p>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setYear(y => y - 1)}
            className="w-7 h-7 rounded-full bg-gray-100 flex items-center justify-center text-gray-500 text-sm"
          >
            &lt;
          </button>
          <span className="text-sm font-medium text-gray-700 w-16 text-center">
            ปี {year + 543}
          </span>
          <button
            onClick={() => setYear(y => y + 1)}
            disabled={year >= currentYear}
            className={[
              'w-7 h-7 rounded-full flex items-center justify-center text-sm',
              year >= currentYear
                ? 'bg-gray-50 text-gray-300 cursor-not-allowed'
                : 'bg-gray-100 text-gray-500',
            ].join(' ')}
          >
            &gt;
          </button>
        </div>
      </div>

      {/* Empty */}
      {history.length === 0 && (
        <div className="flex flex-col items-center justify-center py-16 text-center space-y-2">
          <div className="text-4xl">📋</div>
          <p className="text-sm font-medium text-gray-700">ไม่มีประวัติการลา</p>
          <p className="text-xs text-gray-400">ปี {year + 543}</p>
        </div>
      )}

      {/* List */}
      {history.map((item) => {
        const cfg = STATUS_CONFIG[item.status]
        return (
          <div
            key={item.id}
            className="bg-white border border-gray-100 rounded-xl px-4 py-3 space-y-2"
          >
            {/* Row 1: type + status */}
            <div className="flex items-center justify-between">
              <span className="text-sm font-medium text-gray-900">
                {LEAVE_TYPE_LABELS[item.leave_type]}
              </span>
              <span className={[
                'inline-flex items-center gap-1.5 text-xs font-medium px-2 py-0.5 rounded-full',
                cfg.bg, cfg.text,
              ].join(' ')}>
                <span className={['w-1.5 h-1.5 rounded-full', cfg.dot].join(' ')} />
                {cfg.label}
              </span>
            </div>

            {/* Row 2: date + days */}
            <div className="flex items-center justify-between">
              <span className="text-xs text-gray-500">
                {item.is_half_day
                  ? toThaiDate(item.start_date) + ' (' + (item.half_day_period === 'morning' ? 'เช้า' : 'บ่าย') + ')'
                  : item.start_date === item.end_date
                    ? toThaiDate(item.start_date)
                    : toThaiDate(item.start_date) + ' - ' + toThaiDate(item.end_date)
                }
              </span>
              <span className="text-xs font-medium text-gray-700">{item.days} วัน</span>
            </div>

            {/* Row 3: pending step / approver note */}
            {item.status === 'pending' && (
              <p className="text-xs text-amber-600">
                รอ Step {item.approval_step}/{item.approval_step_max}
              </p>
            )}
            {item.status === 'approved' && item.approved_at && (
              <p className="text-xs text-green-600">
                อนุมัติเมื่อ {toThaiDate(item.approved_at)}
              </p>
            )}
            {item.status === 'rejected' && (
              <p className="text-xs text-red-500">
                {item.approver_note ? item.approver_note : 'ไม่อนุมัติ'}
              </p>
            )}
            {item.is_backdate && (
              <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-purple-50 text-purple-500">
                ย้อนหลัง
              </span>
            )}
          </div>
        )
      })}

    </div>
  )
}
