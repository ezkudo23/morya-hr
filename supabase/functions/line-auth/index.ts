import { createClient } from 'jsr:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  // CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { idToken } = await req.json()

    if (!idToken) {
      return new Response(
        JSON.stringify({ error: 'idToken is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Verify LINE idToken
    const lineVerifyRes = await fetch('https://api.line.me/oauth2/v2.1/verify', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        id_token: idToken,
        client_id: Deno.env.get('LINE_CHANNEL_ID') ?? '',
      }),
    })

    if (!lineVerifyRes.ok) {
      return new Response(
        JSON.stringify({ error: 'Invalid LINE token' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const lineUser = await lineVerifyRes.json()
    const lineUserId = lineUser.sub
    const displayName = lineUser.name
    const pictureUrl = lineUser.picture

    // สร้าง Supabase client (service role)
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    )

    // หา employee จาก line_user_id
    const { data: employee, error: empError } = await supabase
      .from('employees')
      .select('id, employee_code, nickname, role, employment_status')
      .eq('line_user_id', lineUserId)
      .eq('employment_status', 'active')
      .single()

    if (empError || !employee) {
      return new Response(
        JSON.stringify({ error: 'Employee not found or inactive' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // หา profile
    const { data: profile } = await supabase
      .from('profiles')
      .select('role, is_active')
      .eq('employee_id', employee.id)
      .single()

    if (!profile?.is_active) {
      return new Response(
        JSON.stringify({ error: 'Account is inactive' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Sign in หรือ Sign up user ใน Supabase Auth
    const email = `${lineUserId}@line.morya.co.th`

    // ลอง sign in ก่อน
    const { data: signInData, error: signInError } = await supabase.auth.signInWithPassword({
      email,
      password: lineUserId,
    })

    let session = signInData?.session

    // ถ้ายังไม่มี user → สร้างใหม่
    if (signInError) {
      const { data: signUpData, error: signUpError } = await supabase.auth.admin.createUser({
        email,
        password: lineUserId,
        email_confirm: true,
        user_metadata: {
          line_user_id: lineUserId,
          display_name: displayName,
          picture_url: pictureUrl,
          employee_id: employee.id,
          role: profile.role,
        },
      })

      if (signUpError) {
        return new Response(
          JSON.stringify({ error: 'Failed to create user' }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      // Sign in หลัง create
      const { data: newSignIn } = await supabase.auth.signInWithPassword({
        email,
        password: lineUserId,
      })

      session = newSignIn?.session
    }

    // Update last_login
    await supabase
      .from('profiles')
      .update({ last_login: new Date().toISOString() })
      .eq('employee_id', employee.id)

    return new Response(
      JSON.stringify({
        session,
        employee: {
          id: employee.id,
          code: employee.employee_code,
          nickname: employee.nickname,
          role: profile.role,
        },
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})