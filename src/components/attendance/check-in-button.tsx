'use client'

import { useState } from 'react'
import { useAttendance } from '@/hooks/use-attendance'

type Props = {
  employeeId: string
  nickname: string
}

type LastEvent = {
  type: 'check_in' | 'check_out'
  location: string
  isLate: boolean
  lateMinutes: number
  time: string
}

export function CheckInButton({ employeeId, nickname }: Props) {
  const [lastEvent, setLastEvent] = useState<LastEvent | null>(null)
  const [eventType, setEventType] = useState<'check_in' | 'check_out'>('check_in')
  const { recordAttendance, isLoading, error } = useAttendance(employeeId)

  async function handlePress() {
    const result = await recordAttendance(eventType)
    if (!result) return

    const now = new Date()
    const timeStr = now.toLocaleTimeString('th-TH', {
      hour: '2-digit',
      minute: '2-digit',
      timeZone: 'Asia/Bangkok',
    })

    setLastEvent({
      type: eventType,
      location: result.location,
      isLate: result.is_late,
      lateMinutes: result.late_minutes,
      time: timeStr,
    })

    // สลับปุ่ม
    setEventType(eventType === 'check_in' ? 'check_out' : 'check_in')
  }

  return (
    <div className="flex flex-col items-center gap-6 p-6">
      {/* Header */}
      <div className="text-center">
        <p className="text-gray-500 text-sm">สวัสดี</p>
        <h2 className="text-xl font-semibold text-gray-800">{nickname}</h2>
      </div>

      {/* เวลาปัจจุบัน */}
      <div className="text-center">
        <Clock />
      </div>

      {/* ปุ่ม Check-in/out */}
      <button
        onClick={handlePress}
        disabled={isLoading}
        className={`
          w-48 h-48 rounded-full text-white text-xl font-bold shadow-lg
          transition-all duration-200 active:scale-95
          ${isLoading ? 'opacity-50 cursor-not-allowed' : ''}
          ${eventType === 'check_in'
            ? 'bg-green-500 hover:bg-green-600'
            : 'bg-orange-500 hover:bg-orange-600'
          }
        `}
      >
        {isLoading ? (
          <span className="flex flex-col items-center gap-2">
            <div className="w-8 h-8 border-4 border-white border-t-transparent rounded-full animate-spin" />
            <span className="text-sm">กำลังบันทึก...</span>
          </span>
        ) : (
          <span className="flex flex-col items-center gap-1">
            <span className="text-4xl">{eventType === 'check_in' ? '👆' : '👋'}</span>
            <span>{eventType === 'check_in' ? 'เข้างาน' : 'ออกงาน'}</span>
          </span>
        )}
      </button>

      {/* Error */}
      {error && (
        <div className="w-full bg-red-50 border border-red-200 rounded-xl p-4">
          <p className="text-red-600 text-sm text-center">⚠️ {error}</p>
        </div>
      )}

      {/* ผลลัพธ์ */}
      {lastEvent && (
        <div className={`
          w-full rounded-xl p-4 border
          ${lastEvent.isLate
            ? 'bg-red-50 border-red-200'
            : 'bg-green-50 border-green-200'
          }
        `}>
          <div className="text-center">
            <p className="text-lg font-semibold">
              {lastEvent.type === 'check_in' ? '✅ เข้างานแล้ว' : '✅ ออกงานแล้ว'}
            </p>
            <p className="text-gray-600 text-sm mt-1">เวลา {lastEvent.time}</p>
            <p className="text-gray-500 text-xs mt-1">📍 {lastEvent.location}</p>
            {lastEvent.isLate && (
              <p className="text-red-500 text-sm mt-2 font-medium">
                ⏰ สาย {lastEvent.lateMinutes} นาที
              </p>
            )}
          </div>
        </div>
      )}
    </div>
  )
}

// นาฬิกา real-time
function Clock() {
  const [time, setTime] = useState('')

  if (typeof window !== 'undefined') {
    const updateTime = () => {
      const now = new Date()
      setTime(now.toLocaleTimeString('th-TH', {
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit',
        timeZone: 'Asia/Bangkok',
      }))
    }
    updateTime()
    setInterval(updateTime, 1000)
  }

  return (
    <div className="text-center">
      <p className="text-4xl font-mono font-bold text-gray-800">{time}</p>
      <p className="text-gray-500 text-sm mt-1">
        {new Date().toLocaleDateString('th-TH', {
          weekday: 'long',
          year: 'numeric',
          month: 'long',
          day: 'numeric',
          timeZone: 'Asia/Bangkok',
        })}
      </p>
    </div>
  )
}