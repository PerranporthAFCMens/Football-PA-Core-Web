import fs from 'node:fs';
const pages=['index.html','dashboard.html','players.html','match-centre.html','team-settings.html','fixture-sync.html','fixtures.html','voting.html','subs.html','player-portal.html'];
let failed=false;const fail=(file,msg)=>{failed=true;console.error(`FAIL ${file}: ${msg}`)};
for(const file of pages){const html=fs.readFileSync(file,'utf8');const ids=[...html.matchAll(/\bid=["']([^"']+)["']/g)].map(m=>m[1]);const seen=new Set();for(const id of ids){if(seen.has(id))fail(file,`duplicate id "${id}"`);seen.add(id)}const refs=[...html.matchAll(/\$\('([^']+)'\)/g)].map(m=>m[1]);for(const id of new Set(refs)){if(!seen.has(id))fail(file,`JavaScript references missing element #${id}`)}for(const m of html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/gi)){try{new Function(m[1])}catch(e){fail(file,`inline JavaScript syntax error: ${e.message}`)}}if(!html.includes('/core-ui.css'))fail(file,'missing shared /core-ui.css');if(!html.includes('/core-nav.js'))fail(file,'missing shared /core-nav.js');const visible=html.replace(/<script[\s\S]*?<\/script>/gi,' ').replace(/<style[\s\S]*?<\/style>/gi,' ').replace(/<[^>]+>/g,' ').replace(/\s+/g,' ');for(const phrase of ['Saved to Supabase','Synced from Supabase','Core test','browser-only','secure Dev access'])if(visible.toLowerCase().includes(phrase.toLowerCase()))fail(file,`customer-facing debug wording: "${phrase}"`);if(/Club_Logo\.png/i.test(html))fail(file,'hardcoded club logo found');if((html.match(/FootballPANav\.mount/g)||[]).length>1)fail(file,'shared navigation mounted more than once')}
const nav=fs.readFileSync('core-nav.js','utf8');try{new Function(nav)}catch(e){fail('core-nav.js',`syntax error: ${e.message}`)}if(/deploy refresh/i.test(nav))fail('core-nav.js','temporary deployment marker still present');if(!nav.includes("select('scoreboard_token,nav_order')")||!nav.includes('teamItems.sort'))fail('core-nav.js','saved team navigation order is not applied');if(!nav.includes("['voting','Voting'")||!nav.includes("'voting',canManage"))fail('core-nav.js','feature-gated Voting navigation missing');if(!nav.includes("['subs','Subs Tracker'")||!nav.includes("'subs_finance',canManage"))fail('core-nav.js','feature-gated Subs Tracker navigation missing');
const match=fs.readFileSync('match-centre.html','utf8');if(/45\s*\*\s*60|90\s*\*\s*60/.test(match))fail('match-centre.html','hardcoded 45/90 minute match timing found');if(/\.from\(['"]players['"]\)[\s\S]{0,250}\.eq\(['"]club_id['"]/.test(match))fail('match-centre.html','loads club-wide players instead of team_players');if(/['"]in_progress['"]/.test(match))fail('match-centre.html','uses invalid fixture status in_progress');if(/team_side[^\n]{0,80}['"]ours['"]/.test(match))fail('match-centre.html','uses legacy team_side "ours" instead of "us"');if(!match.includes("Six-yard box")||!match.includes("Central box"))fail('match-centre.html','approved goal-zone map is missing');if(!match.includes("set_match_starting_lineup"))fail('match-centre.html','starting lineup is not saved through the dedicated history RPC');if(!match.includes("starting_xi"))fail('match-centre.html','starting lineup confirmation state is not loaded separately from current XI');if(!match.includes("substitutionFromDb"))fail('match-centre.html','saved substitutions are not rebuilt into the event feed');if(!match.includes("syncCompletedState"))fail('match-centre.html','cross-device full-time sync is missing');if(/id=["']assistPlayer["']/.test(match))fail('match-centre.html','redundant main-screen assist selector remains');if(!match.includes('cardPlayerWrap'))fail('match-centre.html','card-only player selector wrapper missing');
const dash=fs.readFileSync('dashboard.html','utf8');if(!dash.includes('teamTab')||!dash.includes('playersTab'))fail('dashboard.html','Team/Players dashboard tabs missing');if(!dash.includes('teamGoalZones')||!dash.includes('teamAssistZones')||!dash.includes('playerGoalZones')||!dash.includes('playerAssistZones'))fail('dashboard.html','dashboard zone analysis missing');if(!dash.includes('teamGoalTypes')||!dash.includes('playerGoalTypes'))fail('dashboard.html','goal type analysis missing');if(!dash.includes('data-player-id')||!dash.includes('renderPlayerDetail')||!dash.includes('playerModal'))fail('dashboard.html','player popup drill-down missing');if(!dash.includes('trainingWindow')||!dash.includes('trainingPercent'))fail('dashboard.html','selectable training attendance percentage missing');if(/<small>Z['"+]/.test(dash)||dash.includes("'<small>Z'+i"))fail('dashboard.html','zone labels still rendered on dashboard pitch');if(!dash.includes('zonePitchSvg'))fail('dashboard.html','Perranporth-style pitch heatmap missing');if(!dash.includes("select('fixture_id,event_type,player_id,related_player_id,minute,stoppage_minute,zone,team_side,details')"))fail('dashboard.html','dashboard does not load goal zone/details data');
const playerHtml=fs.readFileSync('players.html','utf8');if(/Player Dashboard|dash-switch/.test(playerHtml))fail('players.html','stale player-dashboard UI remains');if((playerHtml.match(/FootballPANav\.mount/g)||[]).length!==1)fail('players.html','shared navigation should mount exactly once');
const redirect=fs.readFileSync('training.html','utf8');if(!redirect.includes('/players.html'))fail('training.html','legacy training route does not redirect');
const live=fs.readFileSync('live-score.html','utf8');if(!live.includes('team-scoreboard'))fail('live-score.html','public scoreboard endpoint missing');if(!live.includes('shareBtn'))fail('live-score.html','share control missing');
if(!playerHtml.includes('Save & lock session'))fail('players.html','training session lock control missing');
if(!playerHtml.includes('Surname A–Z'))fail('players.html','player surname sort control missing');
const sync=fs.readFileSync('fixture-sync.html','utf8');if(!sync.includes('fixtureDateHasPassed'))fail('fixture-sync.html','past missing fixtures are not protected');if(!sync.includes('fixture_sync_ignored_updates')||!sync.includes('ignoreChange'))fail('fixture-sync.html','ignored fixture updates are not persisted');
const home=fs.readFileSync('index.html','utf8');if(!home.includes('Coming up'))fail('index.html','Coming up Home card missing');if(/More tools|ACTIVE PLAYERS|Voting|Subs Admin/.test(home))fail('index.html','unsupported or old Home card content remains');if(!home.includes('data-upcoming'))fail('index.html','Coming up fixtures are not rendered');if(!home.includes('trainingShortcut')||!home.includes('dashboardShortcut'))fail('index.html','Home training/dashboard shortcuts missing');if(!home.includes('fixture_sync_ignored_updates'))fail('index.html','Home fixture notice does not respect ignored updates');
if(failed)process.exit(1);console.log('Football PA Core smoke checks passed.');
const portal=fs.readFileSync('player-portal.html','utf8');
for(const rpc of ['player_portal_list_players','player_portal_login','player_portal_first_time_setup','player_portal_change_pin','player_portal_data_v2','player_portal_submit_vote'])if(!portal.includes(rpc))fail('player-portal.html','missing PIN portal RPC '+rpc);
if(!portal.includes("q.get('pin')==='1'"))fail('player-portal.html','legacy-compatible PIN portal mode missing');
if(!portal.includes('historical_team')||!portal.includes('historical'))fail('player-portal.html','historical player/team comparison missing');
if(!dash.includes("eq('include_in_stats',true)"))fail('dashboard.html','dashboard does not exclude fixtures disabled from statistics');
if(!home.includes('include_in_stats!==false'))fail('index.html','Home KPIs do not respect fixture statistics inclusion');
const devTeam=fs.readFileSync('dev-team.html','utf8');if(!devTeam.includes('viewPlayerPortal')||!devTeam.includes('&pin=1'))fail('dev-team.html','Dev Admin player portal preview missing');
if(failed)process.exit(1);

const contextDomain=fs.readFileSync('core-context.js','utf8');
if(!contextDomain.includes("from('team_domains')")||!contextDomain.includes('domain?.team_id'))fail('core-context.js','hostname-aware team routing is missing');
const loginDomain=fs.readFileSync('login.html','utf8');
if(!loginDomain.includes("from('team_domains')")||!loginDomain.includes('location.hostname'))fail('login.html','team-domain branded login is missing');
const devCreateDomain=fs.readFileSync('dev-create-team.html','utf8');
if(!devCreateDomain.includes('.footballpa.com')||!devCreateDomain.includes("from('team_domains')"))fail('dev-create-team.html','subdomain provisioning is missing');
if(failed)process.exit(1);

const teamSettingsNavOrder=fs.readFileSync('team-settings.html','utf8');
if(!teamSettingsNavOrder.includes('Navigation Bar')||!teamSettingsNavOrder.includes('navOrderList')||!teamSettingsNavOrder.includes('normaliseNavOrder'))fail('team-settings.html','Navigation Bar settings missing');
if(!teamSettingsNavOrder.includes('nav_order:normaliseNavOrder()'))fail('team-settings.html','Navigation order is not persisted');
if(failed)process.exit(1);

const keeperSettings=fs.readFileSync('team-settings.html','utf8');
if(!keeperSettings.includes('goalkeeperKitColour')||!keeperSettings.includes('goalkeeper_kit_colour'))fail('team-settings.html','goalkeeper kit colour setting missing');
if(!match.includes('goalkeeper_kit_colour')||!match.includes("toLowerCase()==='gk'")||!match.includes('shirtStriped=!isKeeper&&striped'))fail('match-centre.html','goalkeeper block-colour rendering missing');
if(failed)process.exit(1);

if(!nav.includes("from('team_domains')")||!nav.includes('domainMode=true'))fail('core-nav.js','team-subdomain navigation resolver missing');
if(!nav.includes("teamHref('/voting.html')")||!nav.includes("teamHref('/subs.html')"))fail('core-nav.js','team-aware Voting/Subs links missing');
if(failed)process.exit(1);

const homeDesign=fs.readFileSync('index.html','utf8');
if(!homeDesign.includes('Season at a glance')||!homeDesign.includes('home-shortcut')||!homeDesign.includes('Training Log')||!homeDesign.includes('Dashboard'))fail('index.html','refreshed Home dashboard actions missing');
const sharedUi=fs.readFileSync('core-ui.css','utf8');
if(!sharedUi.includes('Football PA visual refresh v4')||!sharedUi.includes('.home-shortcut')||!sharedUi.includes('--fpa-radius-lg'))fail('core-ui.css','shared visual refresh missing');
if(failed)process.exit(1);

const playfulUi=fs.readFileSync('core-ui.css','utf8');
if(!playfulUi.includes('Football PA visual refresh v5')||!playfulUi.includes('MATCHDAY')||!playfulUi.includes('--fpa-fun-shadow'))fail('core-ui.css','football-focused visual refresh missing');
if(failed)process.exit(1);

if(!nav.includes('head.prepend(btn)')||!nav.includes('fpa-app-head-info'))fail('core-nav.js','hamburger/header identity swap missing');
