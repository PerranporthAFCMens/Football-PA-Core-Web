(function(){
function applyTheme(club){
  const primary=club?.primary_colour||'#1357A6',secondary=club?.secondary_colour||'#FFFFFF';
  const hex=s=>String(s||'').replace('#','');
  const contrast=h=>{const x=hex(h);if(!/^[0-9a-f]{6}$/i.test(x))return '#FFFFFF';const r=parseInt(x.slice(0,2),16),g=parseInt(x.slice(2,4),16),b=parseInt(x.slice(4,6),16),y=(r*299+g*587+b*114)/1000;return y>165?'#102033':'#FFFFFF'};
  const root=document.documentElement;
  root.style.setProperty('--blue',primary);
  root.style.setProperty('--fpa-primary',primary);
  root.style.setProperty('--fpa-secondary',secondary);
  root.style.setProperty('--fpa-accent',primary);
  root.style.setProperty('--fpa-header-text',contrast(primary));
}
async function domainTeam(){
  const host=String(location.hostname||'').toLowerCase();
  if(!host||host==='localhost'||host.endsWith('.vercel.app')||host==='core.footballpa.com'||host==='dev.footballpa.com')return null;
  const {data,error}=await sb.from('team_domains').select('team_id,hostname,team_name,club_name,badge_url,primary_colour,secondary_colour').eq('hostname',host).eq('active',true).maybeSingle();
  if(error)throw error;
  return data||null;
}
async function resolve(opts={}){
  const q=new URLSearchParams(location.search);
  const {data:{session},error:sessionError}=await sb.auth.getSession();
  if(sessionError) throw sessionError;
  if(!session){ const back=location.pathname+location.search; location.replace('./login.html?return='+encodeURIComponent(back)); throw new Error('Not signed in'); }

  const domain=await domainTeam();
  const queryRequested=opts.teamId||q.get('team')||q.get('id');
  const requested=domain?.team_id||queryRequested||localStorage.getItem('fpa_active_team_id');
  const preview=q.get('dev_preview')==='1'&&!domain;
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

  if(domain&&!team) throw new Error('Your account does not have access to this Football PA team.');

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

  const {data:club,error:clubError}=await sb.from('clubs').select('id,name,short_name,primary_colour,secondary_colour,badge_url').eq('id',team.club_id).single();
  if(clubError) throw clubError;
  applyTheme(club);

  let season=null;
  if(team.season_label){
    const {data}=await sb.from('seasons').select('id,label,club_id,active,starts_on,ends_on').eq('club_id',team.club_id).eq('label',team.season_label).maybeSingle();
    season=data||null;
  }
  if(!season){
    const {data}=await sb.from('seasons').select('id,label,club_id,active,starts_on,ends_on').eq('club_id',team.club_id).eq('active',true).order('starts_on',{ascending:false}).limit(1).maybeSingle();
    season=data||null;
  }

  const [featureRes,settingsRes,teamMemberRes,clubMemberRes,platformAdminRes]=await Promise.all([
    sb.from('team_features').select('*').eq('team_id',team.id).maybeSingle(),
    sb.from('team_settings').select('*').eq('team_id',team.id).maybeSingle(),
    sb.from('team_memberships').select('role,permissions').eq('team_id',team.id).eq('user_id',session.user.id).eq('active',true).maybeSingle(),
    sb.from('club_memberships').select('role,permissions').eq('club_id',team.club_id).eq('user_id',session.user.id).eq('active',true).maybeSingle(),
    sb.from('platform_admins').select('user_id').eq('user_id',session.user.id).eq('active',true).maybeSingle()
  ]);
  const teamRole=teamMemberRes.data?.role||null,clubRole=clubMemberRes.data?.role||null;
  const canManage=!!platformAdminRes.data||['team_admin','manager','coach'].includes(teamRole)||['owner','club_admin'].includes(clubRole);

  const previewSuffix=preview?'&dev_preview=1':'';
  const pagesBase=location.hostname.endsWith('.github.io')?('/'+location.pathname.split('/').filter(Boolean)[0]):'';
  const routedPath=path=>pagesBase&&String(path).startsWith('/')?pagesBase+path:path;
  return {
    session,team,club,season,preview,canManage,teamRole,clubRole,domain,
    features:featureRes.data||{},
    settings:settingsRes.data||{},
    href(path,extra=''){
      const cleanExtra=extra?extra.replace(/^&/,''):'';
      const route=routedPath(path);
      if(domain){
        if(!cleanExtra)return route;
        return route+(route.includes('?')?'&':'?')+cleanExtra;
      }
      const glue=route.includes('?')?'&':'?';
      return route+glue+'team='+encodeURIComponent(team.id)+previewSuffix+(cleanExtra?('&'+cleanExtra):'');
    }
  };
}
window.FootballPAContext={resolve,applyTheme,domainTeam};
})();