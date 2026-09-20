(function(){
const STYLE=`
.fpa-nav-btn{position:fixed;top:calc(14px + env(safe-area-inset-top));right:14px;z-index:80;width:48px;height:48px;border:1px solid #cbd6e2;border-radius:15px;background:#fff;color:#102033;box-shadow:0 5px 16px #10203320;font-size:25px;font-weight:900;cursor:pointer}
.fpa-nav-shade{position:fixed;inset:0;background:#0b172666;z-index:81;opacity:0;pointer-events:none;transition:opacity .2s}.fpa-nav-shade.open{opacity:1;pointer-events:auto}
.fpa-nav{position:fixed;inset:0 auto 0 0;width:min(72vw,270px);background:#fff;z-index:82;transform:translateX(-102%);transition:transform .22s ease;box-shadow:18px 0 45px #1020332b;padding:calc(10px + env(safe-area-inset-top)) 10px calc(10px + env(safe-area-inset-bottom));display:flex;flex-direction:column;color:#102033;font-family:Arial,Helvetica,sans-serif}.fpa-nav.open{transform:translateX(0)}
.fpa-nav-head{display:flex;align-items:center;justify-content:space-between;padding:2px 3px 10px;border-bottom:1px solid #d9e3ec}.fpa-nav-team{display:flex;align-items:center;gap:10px;min-width:0}.fpa-nav-badge{width:34px;height:34px;flex:0 0 34px;border-radius:50%;overflow:hidden;background:#eef3f8;display:grid;place-items:center;font-weight:900;color:#1357A6}.fpa-nav-badge img{width:100%;height:100%;object-fit:contain;padding:3px}.fpa-nav-title{display:block;font-size:14px;font-weight:900;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.fpa-nav-club{display:block;color:#6d7b8a;font-size:11px}.fpa-nav-close{border:0;background:transparent;color:#1762ae;font-size:27px;padding:7px;cursor:pointer}
.fpa-nav-links{display:grid;gap:1px;padding:6px 0}.fpa-nav-links a{border-radius:10px;padding:9px 10px;display:flex;align-items:center;gap:10px;text-decoration:none;text-align:left;font-size:17px;font-weight:900;color:#102033}.fpa-nav-links a:active,.fpa-nav-links a.active{background:#eef4fb;color:#1357A6}.fpa-nav-ico{width:22px;text-align:center;font-size:18px}.fpa-nav-foot{margin-top:auto;border-top:1px solid #d9e3ec;padding-top:10px}.fpa-nav-foot button{width:100%;border:0;background:transparent;border-radius:10px;padding:12px;text-align:left;font-weight:800;cursor:pointer;color:#102033}
`;
async function mount(opts={}){
 if(document.getElementById('fpaSharedNav'))return;
 const q=new URLSearchParams(location.search),tid=opts.teamId||q.get('team')||q.get('id');if(!tid)return;
 if(!document.getElementById('fpaSharedNavStyle')){const s=document.createElement('style');s.id='fpaSharedNavStyle';s.textContent=STYLE;document.head.appendChild(s)}
 let features={},team={},club={};
 try{let r=await sb.from('team_features').select('*').eq('team_id',tid).maybeSingle();features=r.data||{};r=await sb.from('teams').select('id,name,club_id,badge_url').eq('id',tid).maybeSingle();team=r.data||{};if(team.club_id){r=await sb.from('clubs').select('name').eq('id',team.club_id).maybeSingle();club=r.data||{}}}catch(e){}
 const preview=q.get('dev_preview')==='1'?'&dev_preview=1':'';
 const items=[['⌂','Home','/index.html?team='+tid+preview,null],['⚽','Match Centre','/match-centre.html?team='+tid+preview,'match_centre'],['👥','Players','/players.html?team='+tid+preview,'players'],['🗳️','Voting','/voting.html?team='+tid+preview,'voting'],['💷','Subs Admin','/subs.html?team='+tid+preview,'subs_finance'],['⚙️','Settings','/team-settings.html?team='+tid+preview,null]].filter(x=>!x[3]||features[x[3]]!==false);
 const shade=document.createElement('div');shade.className='fpa-nav-shade';shade.id='fpaSharedNavShade';
 const nav=document.createElement('aside');nav.className='fpa-nav';nav.id='fpaSharedNav';
 const badge=team.badge_url?'<img src="'+team.badge_url+'" alt="">':'FP';
 nav.innerHTML='<div class="fpa-nav-head"><div class="fpa-nav-team"><div class="fpa-nav-badge">'+badge+'</div><div style="min-width:0"><span class="fpa-nav-title">'+(team.name||'Football PA')+'</span><span class="fpa-nav-club">'+(club.name||'')+'</span></div></div><button class="fpa-nav-close" aria-label="Close menu">×</button></div><nav class="fpa-nav-links">'+items.map(x=>'<a href="'+x[2]+'"><span class="fpa-nav-ico">'+x[0]+'</span>'+x[1]+'</a>').join('')+'</nav><div class="fpa-nav-foot"><button id="fpaNavSignOut">↪ Sign out</button></div>';
 const btn=document.createElement('button');btn.className='fpa-nav-btn';btn.id='fpaSharedNavBtn';btn.setAttribute('aria-label','Open menu');btn.textContent='☰';
 document.body.append(shade,nav,btn);
 const close=()=>{shade.classList.remove('open');nav.classList.remove('open')};btn.onclick=()=>{shade.classList.add('open');nav.classList.add('open')};shade.onclick=close;nav.querySelector('.fpa-nav-close').onclick=close;nav.querySelector('#fpaNavSignOut').onclick=async()=>{await sb.auth.signOut();location.href='/login.html'};
 }
 window.FootballPANav={mount};
})();