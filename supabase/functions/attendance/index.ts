import { createClient } from 'jsr:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// GPS Haversine (ตาม MRD 7.3)
function haversineDistance(
  lat1: number, lon1: number,
  lat2: number, lon2: number
): number {
  const R = 6371000
  const φ1 = (lat1 * Math.PI) / 180
  const φ2 = (lat2 * Math.PI) / 180
  const Δφ = ((lat2 - lat1) * Math.PI) / 180
  const Δλ = ((lon2 - lon1) * Math.PI) / 180
  const a =
    Math.sin(Δφ / 2) * Math.sin(Δφ / 2) +
    Math.cos(φ1) * Math.cos(φ2) *
    Math.sin(Δλ / 2) * Math.sin(Δλ / 2)
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
}

// Hardcode GPS (TODO: DB-driven ก่อน go-live)
const LOCATIONS = [
  { code: 'CC-HQ-WS', lat: 14.886239, lng: 103.492307 },
  { code: 'CC-01', lat: 14.8864189, lng: 103.4919395 },
  { code: 'CC-04', lat: 14.8732376, lng: 103.5060382 },
]
const GPS_RADIUS = 100 // เมตร

function findNearestLocation(userLat: number, userLng: number) {
  let nearest = { code: '', distance: Infinity, isValid: false }
  for (const loc of LOCATIONS) {
    const distance = haversineDistance(userLat, userLng, loc.lat, loc.lng)
    if (distance < nearest.distance) {
      nearest = {
        code: loc.code,
        distance: Math.round(distance),
        isValid: distance <= GPS_RADIUS,
      }
    }
  }
  return nearest
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    )

    const body = await req.json()
    const { employee_id, event_type, latitude, longitude } = body

    console.log('=== attendance called ===')
    console.log('employee_id:', employee_id)
    console.log('event_type:', event_type)
    console.log('GPS:', latitude, longitude)

    // Validate input
    if (!employee_id || !event_type || !latitude || !longitude) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (!['check_in', 'check_out'].includes(event_type)) {
      return new Response(
        JSON.stringify({ error: 'Invalid event_type' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // หา employee
    const { data: employees } = await supabase
      .rpc('get_employee_by_id', { p_employee_id: employee_id })
    const employee = employees?.[0]

    if (!employee) {
      return new Response(
        JSON.stringify({ error: 'Employee not found' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Validate GPS
    const location = findNearestLocation(latitude, longitude)
    console.log('Nearest location:', location.code, 'Distance:', location.distance, 'm')

    if (!location.isValid) {
      return new Response(
        JSON.stringify({
          error: 'GPS_OUT_OF_RANGE',
          message: `อยู่ห่างจากสาขาใกล้ที่สุด ${location.distance} เมตร (ต้องอยู่ใน 100 เมตร)`,
          distance: location.distance,
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Bangkok timezone
    const now = new Date()
    const bangkokTime = new Date(now.toLocaleString('en-US', { timeZone: 'Asia/Bangkok' }))
    const eventDate = bangkokTime.toISOString().split('T')[0]

    // Duplicate prevention (5 นาที — ตาม MRD 7.2)
    const fiveMinutesAgo = new Date(now.getTime() - 5 * 60 * 1000).toISOString()
    const { data: recentLogs } = await supabase
      .from('attendance_logs')
      .select('id, timestamp_reported')
      .eq('employee_id', employee_id)
      .eq('event_type', event_type)
      .eq('event_date', eventDate)
      .gte('timestamp_reported', fiveMinutesAgo)

    if (recentLogs && recentLogs.length > 0) {
      return new Response(
        JSON.stringify({
          error: 'DUPLICATE',
          message: 'บันทึกไปแล้วในช่วง 5 นาทีที่ผ่านมา',
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // หา shift ของวันนี้
    const { data: shiftData } = await supabase
      .from('employee_shifts')
      .select('shift_id, shifts(start_time, end_time)')
      .eq('employee_id', employee_id)
      .eq('work_date', eventDate)
      .single()

    // คำนวณ is_late (check_in เท่านั้น)
    let isLate = false
    let lateMinutes = 0

    if (event_type === 'check_in' && shiftData?.shifts) {
      const shift = shiftData.shifts as { start_time: string; end_time: string }
      const [startHour, startMin] = shift.start_time.split(':').map(Number)
      const shiftStart = new Date(bangkokTime)
      shiftStart.setHours(startHour, startMin, 0, 0)

      if (bangkokTime > shiftStart) {
        isLate = true
        lateMinutes = Math.floor((bangkokTime.getTime() - shiftStart.getTime()) / 60000)
      }
    }

    // หา cost_center_id ของ employee
    const { data: empData } = await supabase
      .from('employees')
      .select('cost_center_id')
      .eq('id', employee_id)
      .single()

    // หา cost_center_id จาก location code
    const { data: actualCC } = await supabase
      .from('cost_centers')
      .select('id')
      .eq('code', location.code)
      .single()

    // Insert attendance log
    const { data: log, error: insertError } = await supabase
      .from('attendance_logs')
      .insert({
        employee_id,
        event_type,
        event_date: eventDate,
        timestamp_reported: now.toISOString(),
        timestamp_accepted: now.toISOString(),
        gps_latitude: latitude,
        gps_longitude: longitude,
        home_cost_center_id: empData?.cost_center_id,
        actual_cost_center_id: actualCC?.id ?? empData?.cost_center_id,
        shift_id: shiftData?.shift_id ?? null,
        is_late: isLate,
        late_minutes: lateMinutes,
      })
      .select()
      .single()

    if (insertError) {
      console.log('Insert error:', insertError.message)
      return new Response(
        JSON.stringify({ error: 'Failed to record attendance', detail: insertError.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Update diligence counter ถ้าสาย
    if (isLate && event_type === 'check_in') {
      const year = bangkokTime.getFullYear()
      const month = bangkokTime.getMonth() + 1

      await supabase.rpc('increment_diligence_counter', {
        p_employee_id: employee_id,
        p_year: year,
        p_month: month,
        p_field: 'late_count',
      })
    }

    console.log('=== attendance success ===', event_type, isLate ? `LATE ${lateMinutes} min` : 'ON TIME')

    return new Response(
      JSON.stringify({
        success: true,
        event_type,
        event_date: eventDate,
        location: location.code,
        distance: location.distance,
        is_late: isLate,
        late_minutes: lateMinutes,
        log_id: log.id,
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.log('=== Unexpected error ===', String(error))
    return new Response(
      JSON.stringify({ error: 'Internal server error', detail: String(error) }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})