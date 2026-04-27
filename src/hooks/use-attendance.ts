'use client'

import { useState } from 'react'
import { getCurrentPosition, findNearestLocation } from '@/lib/gps/haversine'

type AttendanceResult = {
  success: boolean
  event_type: string
  location: string
  distance: number
  is_late: boolean
  late_minutes: number
  error?: string
  message?: string
}

export function useAttendance(employeeId: string) {
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function recordAttendance(
    eventType: 'check_in' | 'check_out'
  ): Promise<AttendanceResult | null> {
    setIsLoading(true)
    setError(null)

    try {
      // ขอ GPS
      const position = await getCurrentPosition()
      const { latitude, longitude } = position.coords

      // เช็ค GPS ฝั่ง client ก่อน (ประหยัด API call)
      const nearest = findNearestLocation(latitude, longitude)
      if (!nearest.isValid) {
        setError(`อยู่ห่างจากสาขา ${nearest.distance} เมตร — ต้องอยู่ใน 100 เมตร`)
        return null
      }

      // ส่งไป Edge Function
      const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!
      const res = await fetch(`${supabaseUrl}/functions/v1/attendance`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          employee_id: employeeId,
          event_type: eventType,
          latitude,
          longitude,
        }),
      })

      const data = await res.json()

      if (!res.ok) {
        setError(data.message ?? data.error ?? 'เกิดข้อผิดพลาด')
        return null
      }

      return data

    } catch (err) {
      setError(err instanceof Error ? err.message : 'เกิดข้อผิดพลาด')
      return null
    } finally {
      setIsLoading(false)
    }
  }

  return { recordAttendance, isLoading, error }
}