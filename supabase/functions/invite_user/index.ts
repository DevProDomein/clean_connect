// @ts-nocheck
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  // Handel CORS preflight requests af (Dit voorkomt de 'Failed to fetch' error in de browser!)
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { email, role, fullName } = await req.json()
    
    // De Service Role Key geeft deze functie 'God-mode' om mensen uit te nodigen
    // (Deze keys worden automatisch door de Supabase omgeving ingevuld)
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { autoRefreshToken: false, persistSession: false } }
    )

    const { data, error } = await supabaseAdmin.auth.admin.inviteUserByEmail(email, {
      // DIT IS CRUCIAAL: Deze data komt in NEW.raw_user_meta_data in de database terecht
      data: { 
        role: role, 
        full_name: fullName 
      },
      // Gebruik de standaard confirmation URL, de redirect regelen we in het dashboard
      redirectTo: 'https://cleanconnect-erp.web.app/set-password', 
    });

    if (error) {
      return new Response(JSON.stringify({ error: error.message }), { 
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400 
      });
    }

    return new Response(JSON.stringify({ user_id: data.user.id }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    })

  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message }), { 
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500 
    });
  }
})

