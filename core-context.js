(function(){
async function resolve(opts={}){
  const q=new URLSearchParams(location.search);
  const {data:{session},error:sessionError}=await sb.auth.getSession();
  if(sessionError) throw sessionError;
  if(!session){ location.replace('/login.html'); throw new Error('Not signed in'); }

  const requested=opts.teamId||q.get('team')||q.get('id')||localStorage.getItem('fpa_active_team_id');
  const preview=q.get('dev_preview')==='1';
  let team=null;

  if(requested){
    if(preview){
      const {data:admin,error:adminError}=await sb.from('platform_admins').select('user_id').eq('user_id',session.user.id).eq('active',true).maybeSingle();
      if(adminError||!admin) throw new Error('Platform admin access required for team preview.');
    }
    const {data,error}=await sb.from('teams').select('id,name,club_id,season_label,age_group,gender,match_format,badge_url,active').eq('id',requested).maybeSingle();
    if(error) throw error;
    team=data;
  }

  if(!team){
    const {data:memberships,error}=await sb.from('team_memberships')
      .select('team_id,teams(id,name,club_id,season_label,age_group,gender,match_format,badge_url,active)')
      .eq('user_id',session.user.id).eq('active',true).limit(20);
    if(error) throw error;
    team=(memberships||[]).map(x=>x.teams).find(Boolean)||null;
  }

  if(!team){
    const {data:clubs,error}=await sb.from('club_memberships').select('club_id').eq('user_id',session.user.id).eq('active',true).limit(20);
    if(error) throw error;
    for(const membership of clubs||[]){
      const {data}=await sb.from('teams').select('id,name,club_id,season_label,age_group,gender,match_format,badge_url,active').eq('club_id',membership.club_id).eq('active',true).order('name').limit(1).maybeSingle();
      if(data){team=data;break}
    }
  }

  if(!team) throw new Error('No Football PA team is available for this account.');
  localStorage.setItem('fpa_active_team_id',team.id);

  const {data:club,error:clubError}=await sb.from('clubs').select('id,name,short_name,primary_colour').eq('id',team.club_id).single();
  if(clubError) throw clubError;

  const [featureRes,settingsRes]=await Promise.all([
    sb.from('team_features').select('*').eq('team_id',team.id).maybeSingle(),
    sb.from('team_settings').select('*').eq('team_id',team.id).maybeSingle()
  ]);

  const previewSuffix=preview?'&dev_preview=1':'';
  return {
    session,team,club,preview,
    features:featureRes.data||{},
    settings:settingsRes.data||{},
    href(path,extra=''){
      const glue=path.includes('?')?'&':'?';
      return path+glue+'team='+encodeURIComponent(team.id)+previewSuffix+(extra?('&'+extra.replace(/^&/,'')):'');
    }
  };
}
window.FootballPAContext={resolve};
})();