// app/payroll/page.tsx
// หน้าหลัก Payroll — Finance/Owner run payroll + ดู summary

'use client'

import { useState } from 'react'
import { useAuth } from '@/hooks/use-auth'
import { createClient } from '@/lib/supabase/client'

const ALLOWED_ROLES = ['owner', 'owner_delegate', 'hr_admin', 'finance']

const MONTH_NAMES = [
  '', 'มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน',
  'พฤษภาคม', 'มิถุนายน', 'กรกฎาคม', 'สิงหาคม',
  'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม',
]

interface RunResult {
  success: boolean
  payroll_run_id?: string
  success_count?: number
  error_count?: number
  total_net_pay?: number
  total_sso?: number
  total_wht?: number
  errors?: { employee_id: string; error: string }[]
  error?: string
}

export default function PayrollPage() {
  const { employee, isLoading: authLoading } = useAuth()
  const supabase = createClient()

  const now = new Date()
  const [year,  setYear]  = useState(now.getFullYear())
  const [month, setMonth] = useState(now.getMonth() + 1)
  const [round, setRound] = useState(1)
  const [running, setRunning]   = useState(false)
  const [result,  setResult]    = useState<RunResult | null>(null)

  const handleRun = async () => {
    if (!employee) return
    setRunning(true)
    setResult(null)
    try {
      const { data, error } = await supabase.rpc('run_payroll', {
        p_year:         year,
        p_month:        month,
        p_round:        round,
        p_initiated_by: employee.profile_id,
      })
      if (error) throw error
      setResult(data as RunResult)
    } catch (err) {
      setResult({ success: false, error: String(err) })
    } finally {
      setRunning(false)
    }
  }

  const formatMoney = (n?: number) =>
    n != null ? n.toLocaleString('th-TH', { minimumFractionDigits: 2 }) : '—'

  if (authLoading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <p className="text-sm text-gray-400">กำลังโหลด...</p>
      </div>
    )
  }

  if (!employee || !ALLOWED_ROLES.includes(employee.role)) {
    return (
      <div className="flex items-center justify-center min-h-screen px-6">
        <div className="text-center space-y-2">
          <p className="text-sm font-medium text-gray-700">ไม่มีสิทธิ์เข้าถึง</p>
          <p className="text-xs text-gray-400">สำหรับ Finance / Owner เท่านั้น</p>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-gray-50">

      {/* Header */}
      <div className="bg-white border-b border-gray-100 px-4 py-3 sticky top-0 z-10">
        <h1 className="text-base font-semibold text-gray-900">Run Payroll</h1>
        <p className="text-xs text-gray-400 mt-0.5">
          {employee.nickname ?? employee.code} · {employee.role}
        </p>
      </div>

      <div className="px-4 py-4 max-w-md mx-auto space-y-4">

        {/* ── ตั้งค่า ───────────────────────────────── */}
        <div className="bg-white border border-gray-200 rounded-2xl px-5 py-4 space-y-4">

          {/* ปี */}
          <div className="space-y-1.5">
            <label className="text-xs font-medium text-gray-500">ปี (พ.ศ.)</label>
            <input
              type="number"
              value={year + 543}
              onChange={e => setYear(Number(e.target.value) - 543)}
              className="w-full border border-gray-200 rounded-xl px-4 py-3 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-300"
            />
          </div>

          {/* เดือน */}
          <div className="space-y-1.5">
            <label className="text-xs font-medium text-gray-500">เดือน</label>
            <select
              value={month}
              onChange={e => setMonth(Number(e.target.value))}
              className="w-full border border-gray-200 rounded-xl px-4 py-3 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-300"
            >
              {MONTH_NAMES.slice(1).map((name, i) => (
                <option key={i + 1} value={i + 1}>{name}</option>
              ))}
            </select>
          </div>

          {/* รอบ */}
          <div className="space-y-1.5">
            <label className="text-xs font-medium text-gray-500">รอบ</label>
            <div className="flex gap-3">
              {[1, 2].map(r => (
                <button
                  key={r}
                  onClick={() => setRound(r)}
                  className={[
                    'flex-1 py-3 rounded-xl text-sm font-medium border transition-all',
                    round === r
                      ? 'bg-blue-500 text-white border-blue-500'
                      : 'bg-white text-gray-500 border-gray-200',
                  ].join(' ')}
                >
                  {r === 1 ? 'รอบ 1 — เงินเดือน' : 'รอบ 2 — Commission'}
                </button>
              ))}
            </div>
          </div>

          {/* Summary line */}
          <div className="bg-gray-50 rounded-xl px-4 py-2.5">
            <p className="text-xs text-gray-500 text-center">
              Payroll {MONTH_NAMES[month]} {year + 543} · รอบ {round}
              {round === 1 ? ' (เงินเดือน)' : ' (Commission)'}
            </p>
          </div>

          {/* Run button */}
          <button
            onClick={handleRun}
            disabled={running}
            className={[
              'w-full py-3.5 rounded-xl text-sm font-semibold transition-all',
              running
                ? 'bg-gray-100 text-gray-400 cursor-not-allowed'
                : 'bg-blue-500 text-white active:scale-[0.98]',
            ].join(' ')}
          >
            {running ? 'กำลังคำนวณ...' : `Run Payroll รอบ ${round}`}
          </button>
        </div>

        {/* ── ผลลัพธ์ ──────────────────────────────── */}
        {result && (
          <div className={[
            'border rounded-2xl px-5 py-4 space-y-3',
            result.success
              ? 'bg-green-50 border-green-200'
              : 'bg-red-50 border-red-200',
          ].join(' ')}>

            {result.success ? (
              <>
                <div className="flex items-center gap-2">
                  <span className="text-lg">✅</span>
                  <p className="text-sm font-semibold text-green-800">
                    Run สำเร็จ — {result.success_count} คน
                  </p>
                </div>

                <div className="space-y-1.5 text-xs">
                  <div className="flex justify-between">
                    <span className="text-gray-500">รวม Net Pay</span>
                    <span className="font-semibold text-gray-900">
                      ฿{formatMoney(result.total_net_pay)}
                    </span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-gray-500">รวม SSO (พนักงาน)</span>
                    <span className="text-gray-700">฿{formatMoney(result.total_sso)}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-gray-500">รวม WHT</span>
                    <span className="text-gray-700">฿{formatMoney(result.total_wht)}</span>
                  </div>
                </div>

                {result.error_count && result.error_count > 0 ? (
                  <div className="bg-amber-50 border border-amber-200 rounded-xl px-3 py-2">
                    <p className="text-xs text-amber-700 font-medium">
                      ⚠️ มี {result.error_count} คนที่คำนวณไม่สำเร็จ
                    </p>
                    {result.errors?.map((e, i) => (
                      <p key={i} className="text-xs text-amber-600 mt-0.5">
                        {e.employee_id}: {e.error}
                      </p>
                    ))}
                  </div>
                ) : null}

                <p className="text-xs text-green-600 text-center">
                  Payroll Run ID: {result.payroll_run_id?.slice(0, 8)}...
                </p>
              </>
            ) : (
              <div className="flex items-center gap-2">
                <span className="text-lg">❌</span>
                <p className="text-sm font-medium text-red-700">{result.error}</p>
              </div>
            )}
          </div>
        )}

      </div>
    </div>
  )
}