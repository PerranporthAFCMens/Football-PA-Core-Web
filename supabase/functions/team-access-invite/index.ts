import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors={
  "Access-Control-Allow-Origin":"*",
  "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods":"POST, OPTIONS"
};
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json"}});

Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
  if(req.method!=="POST")return json({error:"Method not allowed"},405);
  try{
    const authHeader=req.headers.get("Authorization")||"";
    if(!authHeader.startsWith("Bearer "))return json({error:"Authentication required"},401);

    const url=Deno.env.get("SUPABASE_URL")!;
    const anon=Deno.env.get("SUPABASE_ANON_KEY")||"sb_publishable_3ibkYwM0fFdHgKdGFIN5cQ_BT_WudUW";
    const service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const caller=createClient(url,anon,{global:{headers:{Authorization:authHeader}},auth:{persistSession:false,autoRefreshToken:false}});
    const admin=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});

    const {data:{user},error:userError}=await caller.auth.getUser();
    if(userError||!user)return json({error:"Authentication required"},401);

    const body=await req.json().catch(()=>({}));
    const teamId=String(body.team_id||"");
    const email=String(body.email||"").trim().toLowerCase();
    const role=String(body.role||"");
    const accessLevelId=body.access_level_id?String(body.access_level_id):null;
    const name=String(body.name||"").trim().slice(0,80);
    if(!teamId||!email)return json({error:"Team and email are required"},400);

    // Permission check and team access (the database function refuses anyone without Access Management permission).
    const {data:prepared,error:prepareError}=await caller.rpc("prepare_team_access_invite",{
      p_team_id:teamId,p_email:email,p_role:role,p_access_level_id:accessLevelId
    });
    if(prepareError)return json({error:prepareError.message},403);

    // Remember the name on the invite so it shows in Pending invitations.
    if(name){
      await admin.from("pending_team_access").update({display_name:name,updated_at:new Date().toISOString()})
        .eq("team_id",teamId).eq("email",email);
    }

    if(prepared?.status==="existing_account"){
      // Fill in their name only if their account does not have one yet.
      if(name&&prepared?.user_id){
        await admin.from("profiles").update({display_name:name}).eq("id",prepared.user_id).is("display_name",null);
      }
      return json({ok:true,status:"existing_account",email,message:"Access added to the existing Football PA account."});
    }

    const {data:team,error:teamError}=await admin.from("teams")
      .select("id,name,club_id,badge_url,clubs(name,primary_colour,badge_url)")
      .eq("id",teamId).single();
    if(teamError||!team)return json({error:"Team not found"},404);
    const club=Array.isArray(team.clubs)?team.clubs[0]:team.clubs;
    const redirectTo="https://core.footballpa.com/team-invite.html?team="+encodeURIComponent(teamId);

    const {data:invited,error:inviteError}=await admin.auth.admin.inviteUserByEmail(email,{
      redirectTo,
      data:{
        display_name:name||undefined,
        footballpa_team_id:teamId,
        footballpa_team_name:team.name||"",
        footballpa_club_name:club?.name||team.name||"Football PA",
        footballpa_badge_url:team.badge_url||club?.badge_url||"",
        footballpa_primary_colour:club?.primary_colour||"#1357A6",
        footballpa_staff_invite:true,
        footballpa_staff_role:role
      }
    });
    if(inviteError){
      return json({error:inviteError.message,pending:true,message:"Access is prepared, but the invitation email could not be sent."},409);
    }

    return json({
      ok:true,status:"invited",email,user_id:invited.user?.id||null,
      message:"Invitation email sent."
    });
  }catch(e){
    return json({error:e instanceof Error?e.message:"Unable to send invitation"},500);
  }
});
