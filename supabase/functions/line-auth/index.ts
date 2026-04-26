import { createClient } from 'jsr:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const body = await req.json()
    console.log('=== line-auth called ===')
    console.log('accessToken received:', body.accessToken ? 'yes' : 'no')

    const { accessToken } = body

    if (!accessToken) {
      return new Response(
        JSON.stringify({ error: 'accessToken is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Verify accessToken กับ LINE
    const lineVerifyRes = await fetch(
      `https://api.line.me/oauth2/v2.1/verify?access_token=${accessToken}`
    )
    const lineVerifyBody = await lineVerifyRes.json()
    console.log('LINE verify status:', lineVerifyRes.status)
    console.log('LINE verify body:', JSON.stringify(lineVerifyBody))

    if (!lineVerifyRes.ok) {
      return new Response(
        JSON.stringify({ error: 'Invalid LINE token', detail: lineVerifyBody }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // ดึง profile จาก LINE
    const lineProfileRes = await fetch('https://api.line.me/v2/profile', {
      headers: { Authorization: `Bearer ${accessToken}` },
    })
    const lineProfile = await lineProfileRes.json()
    console.log('LINE profile:', JSON.stringify(lineProfile))

    const lineUserId = lineProfile.userId
    const displayName = lineProfile.displayName
    const pictureUrl = lineProfile.pictureUrl

    if (!lineUserId) {
      return new Response(
        JSON.stringify({ error: 'Cannot get LINE user ID' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log('LINE User ID:', lineUserId)

    // Debug service key
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const serviceKey = Deno.env.get('MY_SERVICE_KEY') ?? ''
    console.log('SUPABASE_URL:', supabaseUrl)
    console.log('Service key length:', serviceKey.length)
    console.log('Service key prefix:', serviceKey.substring(0, 30))

    // สร้าง Supabase client
    const supabase = createClient(supabaseUrl, serviceKey)

    // หา employee จาก line_user_id ผ่าน RPC (bypass RLS)
    const { data: employees, error: empError } = await supabase
     .rpc('get_employee_by_line_id', { p_line_user_id: lineUserId })

    const employee = employees?.[0] ?? null

    console.log('Employee found:', employee ? employee.nickname : 'not found')
    console.log('Employee error:', empError ? empError.message : 'none')

    if (empError || !employee) {
      return new Response(
        JSON.stringify({
          error: 'Employee not found',
          debug_line_user_id: lineUserId,
        }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // หา profile ผ่าน RPC (bypass RLS)
     const { data: profiles, error: profileError } = await supabase
      .rpc('get_profile_by_employee_id', { p_employee_id: employee.id })

    const profile = profiles?.[0] ?? null

    console.log('Profile found:', profile ? profile.role : 'not found')
    console.log('Profile error:', profileError ? profileError.message : 'none')

    if (!profile?.is_active) {
      return new Response(
        JSON.stringify({ error: 'Account is inactive' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Sign in หรือ Sign up
    const email = `${lineUserId}@line.morya.co.th`

    const { data: signInData, error: signInError } = await supabase.auth.signInWithPassword({
      email,
      password: lineUserId,
    })

    console.log('Sign in error:', signInError ? signInError.message : 'none')

    let session = signInData?.session

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

      console.log('Sign up error:', signUpError ? signUpError.message : 'none')

      if (signUpError) {
        return new Response(
          JSON.stringify({ error: 'Failed to create user', detail: signUpError.message }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

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

    console.log('=== Auth success ===')

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
    console.log('=== Unexpected error ===')
    console.log(String(error))
    return new Response(
      JSON.stringify({ error: 'Internal server error', detail: String(error) }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})