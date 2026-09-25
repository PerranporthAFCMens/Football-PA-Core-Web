import fs from 'node:fs';
const pages=['index.html','dashboard.html','players.html','match-centre.html','team-settings.html','fixture-sync.html','fixtures.html','availability.html','voting.html','subs.html','player-portal.html'];
let failed=false;const fail=(file,msg)=>{failed=true;console.error(`FAIL ${file}: ${msg}`)};
for(const file of pages){const html=fs.readFileSync(file,'utf8');const ids=[...html.matchAll(/\bid=["']([^"']+)["']/g)].map(m=>m[1]);const seen=new Set();for(const id of ids){if(seen.has(id))fail(file,`duplicate id "${id}"`);seen.add(id)}const refs=[...html.matchAll(/\$\('([^']+)'\)/g)].map(m=>m[1]);for(const id of new Set(refs)){if(!seen.has(id))fail(file,`JavaScript references missing element #${id}`)}for(const m of html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/gi)){try{new Function(m[1])}catch(e){fail(file,`inline JavaScript syntax error: ${e.message}`)}}if(!html.includes('/core-ui.css'))fail(file,'missing shared /core-ui.css');if(!html.includes('/core-nav.js'))fail(file,'missing shared /core-nav.js');const visible=html.replace(/<script[\s\S]*?<\/script>/gi,' ').replace(/<style[\s\S]*?<\/style>/gi,' ').replace(/<[^>]+>/g,' ').replace(/\s+/g,' ');for(const phrase of ['Saved to Supabase','Synced from Supabase','Core test','browser-only','secure Dev access'])if(visible.toLowerCase().includes(phrase.toLowerCase()))fail(file,`customer-facing debug wording: "${phrase}"`);if(/Club_Logo\.png/i.test(html))fail(file,'hardcoded club logo found');if((html.match(/FootballPANav\.mount/g)||[]).length>1)fail(file,'shared navigation mounted more than once')}
const coreClient=fs.readFileSync('core-client.js','utf8');try{new Function(coreClient)}catch(e){fail('core-client.js',`syntax error: ${e.message}`)}if((coreClient.match(/supabase\.createClient\(/g)||[]).length!==1)fail('core-client.js','shared Supabase client should be created exactly once');if(!coreClient.includes('FootballPAClient'))fail('core-client.js','shared FootballPAClient global missing');
const context=fs.readFileSync('core-context.js','utf8');try{new Function(context)}catch(e){fail('core-context.js',`syntax error: ${e.message}`)}if(!context.includes("get_team_access_context")||!context.includes("capabilities:access"))fail('core-context.js','authoritative team access context is not wired in');
const nav=fs.readFileSync('core-nav.js','utf8');try{new Function(nav)}catch(e){fail('core-nav.js',`syntax error: ${e.message}`)}if(/deploy refresh/i.test(nav))fail('core-nav.js','temporary deployment marker still present');if(!nav.includes("get_team_access_context")||!nav.includes('access.can_manage_match')||!nav.includes('access.can_manage_voting')||!nav.includes('access.can_manage_subs')||!nav.includes('access.can_manage_team'))fail('core-nav.js','capability-based navigation access is missing');if(!nav.includes("select('scoreboard_token,nav_order')")||!nav.includes('teamItems.sort'))fail('core-nav.js','saved team navigation order is not applied');if(!nav.includes("['voting','Voting'")||!nav.includes('access.can_manage_voting'))fail('core-nav.js','feature-gated Voting navigation missing');if(!nav.includes("['subs','Subs Tracker'")||!nav.includes('access.can_manage_subs'))fail('core-nav.js','feature-gated Subs Tracker navigation missing');if(!nav.includes("['availability','Availability'")||!nav.includes("'availability',true"))fail('core-nav.js','feature-gated Availability navigation missing');
const playersAccess=fs.readFileSync('players.html','utf8');if(!playersAccess.includes('can_manage_players'))fail('players.html','Players does not use the shared players capability');
const fixturesAccess=fs.readFileSync('fixtures.html','utf8');if(!fixturesAccess.includes('can_manage_fixtures'))fail('fixtures.html','Fixtures does not use the shared fixtures capability');
const syncAccess=fs.readFileSync('fixture-sync.html','utf8');if(!syncAccess.includes('can_manage_fixtures'))fail('fixture-sync.html','Fixture Sync does not use the shared fixtures capability');
const settingsAccess=fs.readFileSync('team-settings.html','utf8');if(!settingsAccess.includes("get_team_access_context")||!settingsAccess.includes('can_manage_team'))fail('team-settings.html','Team Settings does not use the shared team-management capability');
const match=fs.readFileSync('match-centre.html','utf8');if(!match.includes('can_manage_match'))fail('match-centre.html','Match Centre does not enforce the shared match capability');if(/45\s*\*\s*60|90\s*\*\s*60/.test(match))fail('match-centre.html','hardcoded 45/90 minute match timing found');if(/\.from\(['"]players['"]\)[\s\S]{0,250}\.eq\(['"]club_id['"]/.test(match))fail('match-centre.html','loads club-wide players instead of team_players');if(/['"]in_progress['"]/.test(match))fail('match-centre.html','uses invalid fixture status in_progress');if(/team_side[^\n]{0,80}['"]ours['"]/.test(match))fail('match-centre.html','uses legacy team_side "ours" instead of "us"');if(!match.includes("Six-yard box")||!match.includes("Central box"))fail('match-centre.html','approved goal-zone map is missing');if(!match.includes("set_match_starting_lineup"))fail('match-centre.html','starting lineup is not saved through the dedicated history RPC');if(!match.includes("starting_xi"))fail('match-centre.html','starting lineup confirmation state is not loaded separately from current XI');if(!match.includes("oldXi[slot.k]")||!match.includes("Preserve an existing player's exact tactical slot"))fail('match-centre.html','saved lineup slots are not preserved on reload');if(/ensureFormation\([^)]*\)\{[^}]*Object\.values\(state\.xi\|\|\{\}\)/.test(match))fail('match-centre.html','lineup reload still rebuilds XI from unordered object values');if(!match.includes("substitutionFromDb"))fail('match-centre.html','saved substitutions are not rebuilt into the event feed');if(!match.includes("syncCompletedState"))fail('match-centre.html','cross-device full-time sync is missing');if(/id=["']assistPlayer["']/.test(match))fail('match-centre.html','redundant main-screen assist selector remains');if(!match.includes('cardPlayerWrap'))fail('match-centre.html','card-only player selector wrapper missing');
const dash=fs.readFileSync('dashboard.html','utf8');if(!dash.includes('teamTab')||!dash.includes('playersTab'))fail('dashboard.html','Team/Players dashboard tabs missing');if(!dash.includes('teamGoalZones')||!dash.includes('teamAssistZones')||!dash.includes('playerGoalZones')||!dash.includes('playerAssistZones'))fail('dashboard.html','dashboard zone analysis missing');if(!dash.includes('teamGoalTypes')||!dash.includes('playerGoalTypes'))fail('dashboard.html','goal type analysis missing');if(!dash.includes('data-player-id')||!dash.includes('renderPlayerDetail')||!dash.includes('playerModal'))fail('dashboard.html','player popup drill-down missing');if(!dash.includes('trainingWindow')||!dash.includes('trainingPercent'))fail('dashboard.html','selectable training attendance percentage missing');if(/<small>Z['"+]/.test(dash)||dash.includes("'<small>Z'+i"))fail('dashboard.html','zone labels still rendered on dashboard pitch');if(!dash.includes('zonePitchSvg'))fail('dashboard.html','Perranporth-style pitch heatmap missing');if(!dash.includes("select('fixture_id,event_type,player_id,related_player_id,minute,stoppage_minute,zone,team_side,details')"))fail('dashboard.html','dashboard does not load goal zone/details data');
const playerHtml=fs.readFileSync('players.html','utf8');if(/Player Dashboard|dash-switch/.test(playerHtml))fail('players.html','stale player-dashboard UI remains');if((playerHtml.match(/FootballPANav\.mount/g)||[]).length!==1)fail('players.html','shared navigation should mount exactly once');
const redirect=fs.readFileSync('training.html','utf8');if(!redirect.includes('/players.html'))fail('training.html','legacy training route does not redirect');
const live=fs.readFileSync('live-score.html','utf8');if(!live.includes('team-scoreboard'))fail('live-score.html','public scoreboard endpoint missing');if(!live.includes('shareBtn'))fail('live-score.html','share control missing');
if(!playerHtml.includes('Save & lock session'))fail('players.html','training session lock control missing');
if(!playerHtml.includes('Surname A–Z'))fail('players.html','player surname sort control missing');
const sync=fs.readFileSync('fixture-sync.html','utf8');if(!sync.includes('fixtureDateHasPassed'))fail('fixture-sync.html','past missing fixtures are not protected');if(!sync.includes('fixture_sync_ignored_updates')||!sync.includes('ignoreChange'))fail('fixture-sync.html','ignored fixture updates are not persisted');
const home=fs.readFileSync('index.html','utf8');const homeVisible=home.replace(/<script[\s\S]*?<\/script>/gi,' ').replace(/<style[\s\S]*?<\/style>/gi,' ').replace(/<[^>]+>/g,' ').replace(/\s+/g,' ');if(!home.includes('Coming up'))fail('index.html','Coming up Home card missing');if(/More tools|ACTIVE PLAYERS|Subs Admin/.test(homeVisible))fail('index.html','unsupported or old Home card content remains');if(!home.includes('data-upcoming'))fail('index.html','Coming up fixtures are not rendered');if(!home.includes('homeShortcut1')||!home.includes('homeShortcut2')||!home.includes('renderHomeShortcut'))fail('index.html','configurable Home shortcuts missing');if(!home.includes('fixture_sync_ignored_updates'))fail('index.html','Home fixture notice does not respect ignored updates');
if(failed)process.exit(1);console.log('Football PA Core smoke checks passed.');
const portal=fs.readFileSync('player-portal.html','utf8');
for(const rpc of ['player_portal_list_players','player_portal_list_players_v2','player_portal_login','player_portal_login_v2','player_portal_first_time_setup','player_portal_first_time_setup_v2','player_portal_change_pin','player_portal_data_v2','player_portal_submit_vote','player_portal_availability','player_portal_set_availability'])if(!portal.includes(rpc))fail('player-portal.html','missing PIN portal RPC '+rpc);
if(!portal.includes("q.get('pin')==='1'"))fail('player-portal.html','legacy-compatible PIN portal mode missing');if(!portal.includes("q.get('portal')")||!portal.includes('p_portal_token:PORTAL_TOKEN'))fail('player-portal.html','protected Player Portal token support missing');
if(!portal.includes('historical_team')||!portal.includes('historical'))fail('player-portal.html','historical player/team comparison missing');
if(!dash.includes("eq('include_in_stats',true)"))fail('dashboard.html','dashboard does not exclude fixtures disabled from statistics');
if(!home.includes('include_in_stats!==false'))fail('index.html','Home KPIs do not respect fixture statistics inclusion');
const devTeam=fs.readFileSync('dev-team.html','utf8');if(!devTeam.includes('viewPlayerPortal')||!devTeam.includes('&pin=1'))fail('dev-team.html','Dev Admin player portal preview missing');if(!devTeam.includes('player_portal_token')||!devTeam.includes('&portal='))fail('dev-team.html','Dev Admin Player Portal preview is missing the protected token');
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
if(!teamSettingsNavOrder.includes('nav_order:normaliseNavOrder()'))fail('team-settings.html','Navigation order is not persisted');if(!teamSettingsNavOrder.includes("'availability'")||!teamSettingsNavOrder.includes("availability:'Availability'"))fail('team-settings.html','Availability is missing from configurable navigation');
if(failed)process.exit(1);

const keeperSettings=fs.readFileSync('team-settings.html','utf8');
if(!keeperSettings.includes('goalkeeperKitColour')||!keeperSettings.includes('goalkeeper_kit_colour'))fail('team-settings.html','goalkeeper kit colour setting missing');
if(!match.includes('goalkeeper_kit_colour')||!match.includes("toLowerCase()==='gk'")||!match.includes('shirtStriped=!isKeeper&&striped'))fail('match-centre.html','goalkeeper block-colour rendering missing');
if(failed)process.exit(1);

if(!nav.includes("from('team_domains')")||!nav.includes('domainMode=true'))fail('core-nav.js','team-subdomain navigation resolver missing');
if(!nav.includes("teamHref('/voting.html')")||!nav.includes("teamHref('/subs.html')"))fail('core-nav.js','team-aware Voting/Subs links missing');
if(failed)process.exit(1);

const homeDesign=fs.readFileSync('index.html','utf8');
if(!homeDesign.includes('Season at a glance')||!homeDesign.includes('home-shortcut')||!homeDesign.includes('HOME_SHORTCUTS'))fail('index.html','refreshed configurable Home actions missing');
const sharedUi=fs.readFileSync('core-ui.css','utf8');
if(!sharedUi.includes('Football PA visual refresh v4')||!sharedUi.includes('.home-shortcut')||!sharedUi.includes('--fpa-radius-lg'))fail('core-ui.css','shared visual refresh missing');
if(failed)process.exit(1);

const playfulUi=fs.readFileSync('core-ui.css','utf8');
if(!playfulUi.includes('Football PA visual refresh v5')||!playfulUi.includes('MATCHDAY')||!playfulUi.includes('--fpa-fun-shadow'))fail('core-ui.css','football-focused visual refresh missing');
if(failed)process.exit(1);

if(!nav.includes('head.prepend(btn)')||!nav.includes('fpa-app-head-info'))fail('core-nav.js','hamburger/header identity swap missing');

const subsFixture=fs.readFileSync('subs.html','utf8');
if(!subsFixture.includes('Select player…')||!subsFixture.includes('Select match…')||!subsFixture.includes('get_subs_tracker_v2'))fail('subs.html','player/match picker subs UX missing');
if(!subsFixture.includes('Copy matches + payment link')||!subsFixture.includes('set_subs_match_status'))fail('subs.html','full player subs file workflow missing');
if(!subsFixture.includes('No squad has been saved for this fixture yet'))fail('subs.html','pre-match fixture fallback missing');
if(failed)process.exit(1);

const availability=fs.readFileSync('availability.html','utf8');
if(!availability.includes('get_team_availability')||!availability.includes('save_fixture_squad'))fail('availability.html','availability data/squad RPC wiring missing');
if(!availability.includes('set_player_fixture_availability')||!availability.includes('data-set-player-avail'))fail('availability.html','manager availability override controls missing');
if(!availability.includes('Share to WhatsApp')||!availability.includes('tab=availability&fixture='))fail('availability.html','weekly WhatsApp availability share flow missing');
if(!availability.includes('Season availability')||!availability.includes('response_rate_pct'))fail('availability.html','season availability reporting missing');
if(!portal.includes('data-tab="availability"')||!portal.includes('data-avail-answer="true"')||!portal.includes('data-avail-answer="false"'))fail('player-portal.html','Yes/No Availability poll UI missing');
if(failed)process.exit(1);

const votingCentre=fs.readFileSync('voting.html','utf8');if(!votingCentre.includes('player_portal_token')||!votingCentre.includes('&portal='))fail('voting.html','Voting share link is missing the protected Player Portal token');
if(!votingCentre.includes('Voting match')||!votingCentre.includes('get_voting_centre')||!votingCentre.includes('get_voting_match_snapshot'))fail('voting.html','Voting Centre match-picker history missing');
if(!votingCentre.includes('Season Voting Table')||!votingCentre.includes('can_view_private_report'))fail('voting.html','private season report link missing');
const votingSeason=fs.readFileSync('voting-season.html','utf8');
if(!votingSeason.includes('get_private_voting_season_report')||!votingSeason.includes('Pts/Game')||!votingSeason.includes('MOTM')||!votingSeason.includes('DOD'))fail('voting-season.html','private season voting table missing');
if(failed)process.exit(1);

const legacyVoting=fs.readFileSync('voting.html','utf8');
if(!legacyVoting.includes('Voting match')||!legacyVoting.includes('Open voting')||!legacyVoting.includes('Close voting'))fail('voting.html','legacy Voting Centre controls missing');
if(!legacyVoting.includes("Who\\'s voted")||!legacyVoting.includes('Still to vote')||!legacyVoting.includes('Dick of the Day'))fail('voting.html','legacy Voting Centre result sections missing');
if(!legacyVoting.includes('get_voting_match_snapshot')||!legacyVoting.includes('set_voting_open_event'))fail('voting.html','Voting Centre Core RPC wiring missing');
const portalVote=fs.readFileSync('player-portal.html','utf8');
if(!portalVote.includes("const wanted=q.get('tab')")||!portalVote.includes("['availability','vote'].includes(wanted)"))fail('player-portal.html','direct Availability/Vote tab link support missing');
if(failed)process.exit(1);

const votingShared=fs.readFileSync('voting.html','utf8');if(!votingShared.includes('./core-ui.css')||!votingShared.includes('./core-nav.js')||!votingShared.includes('FootballPANav.mount'))fail('voting.html','Voting Centre must use shared Football PA shell');
if(failed)process.exit(1);

const matchTactical=fs.readFileSync('match-centre.html','utf8');
if(matchTactical.includes('function openPicker(slot){if(lineupSaved)return;'))fail('match-centre.html','saved lineup still blocks tactical player picker');
if(!matchTactical.includes('.pitch.format-11 .slot-shirt .shirt-number{font-size:25px}')||!matchTactical.includes('.pitch.format-11 .slot-shirt .shirt-number{font-size:16px}'))fail('match-centre.html','reduced 11-a-side shirt numbers missing');if(!matchTactical.includes('function eligiblePlayers()')||!matchTactical.includes('matchSquadIds.length'))fail('match-centre.html','saved match squad is not used as the Match Centre player pool');
if(failed)process.exit(1);

const votingOrder=fs.readFileSync('voting.html','utf8');if(!votingOrder.includes(".order('kick_off',{ascending:true})"))fail('voting.html','Voting match picker must be chronological');if(failed)process.exit(1);

const matchEventsEdit=fs.readFileSync('match-centre.html','utf8');
if(!matchEventsEdit.includes('data-edit-event')||!matchEventsEdit.includes('saveEventEdit')||!matchEventsEdit.includes('Edit event'))fail('match-centre.html','event editing controls missing');
if(!matchEventsEdit.includes('Share result')||!matchEventsEdit.includes('FA Full-Time events')||!matchEventsEdit.includes('navigator.share'))fail('match-centre.html','completed-match share tools missing');if(!matchEventsEdit.includes('Share lineup image')||!matchEventsEdit.includes('Preview image')||!matchEventsEdit.includes('buildLineupCanvas')||!matchEventsEdit.includes("new File([blob],lineupShareFileName()"))fail('match-centre.html','shareable lineup image tools missing');
if(!matchEventsEdit.includes("String(ev.team_side||'us')!=='opponent'"))fail('match-centre.html','goal score side-aware delete/edit logic missing');
if(failed)process.exit(1);

const matchDeps=fs.readFileSync('match-centre.html','utf8');
if(!matchDeps.includes('src="./core-context.js"')||!matchDeps.includes('src="./core-nav.js"'))fail('match-centre.html','relative Core dependencies missing');
if(!matchDeps.includes("ensureCoreDependency('FootballPAContext'")||!matchDeps.includes("ensureCoreDependency('FootballPANav'"))fail('match-centre.html','Core dependency fallback loader missing');
if(failed)process.exit(1);

const rootHtmlFiles=fs.readdirSync('.').filter(f=>f.endsWith('.html'));

for(const file of rootHtmlFiles){
  const html=fs.readFileSync(file,'utf8');
  if(html.includes('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2')){
    if(!html.includes('src="./core-client.js"'))fail(file,'Supabase page is missing shared core-client.js');
    if(html.includes('supabase.createClient('))fail(file,'page still creates its own Supabase client');
    const cdnPos=html.indexOf('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2'),clientPos=html.indexOf('src="./core-client.js"');
    if(clientPos<cdnPos)fail(file,'core-client.js loads before the Supabase library');
  }
  if(html.includes('src="/core-context.js"')||html.includes('src="/core-nav.js"')||html.includes('href="/core-ui.css"'))fail(file,'root-relative shared Core dependency remains');
  for(const m of html.matchAll(/(?:href|action)=["']\/(?!\/)[^"']*\.html[^"']*["']/g))fail(file,'unsafe root-relative HTML navigation: '+m[0]);
  for(const m of html.matchAll(/(?:location(?:\.href|\.replace)?|window\.location(?:\.href)?)\s*(?:=|\()\s*["']\/(?!\/)/g))fail(file,'unsafe root-relative JavaScript navigation: '+m[0]);
  if(/location\.origin\s*\+\s*["']\/[^"']*\.html/.test(html))fail(file,'unsafe root-relative callback URL');
}
const forcedNumbers=fs.readFileSync('match-centre.html','utf8');
if(!forcedNumbers.includes("String(team?.match_format||'11-a-side').toLowerCase().includes('11')?24:34"))fail('match-centre.html','inline format-aware SVG shirt number size missing');
if(failed)process.exit(1);

const navPathSafe=fs.readFileSync('core-nav.js','utf8');
if(!navPathSafe.includes("location.hostname.endsWith('.github.io')")||!navPathSafe.includes("const routedPath=path=>pagesBase"))fail('core-nav.js','GitHub Pages project-path routing missing');
if(!navPathSafe.includes("const route=routedPath(path)"))fail('core-nav.js','teamHref does not use project-path routing');
if(failed)process.exit(1);

const pagesBuilder=fs.readFileSync('scripts/build-pages-preview.mjs','utf8');
if(pagesBuilder.includes("replace(/([\"'\`])\\/(?!\\/)/g"))fail('build-pages-preview.mjs','preview builder must not rewrite arbitrary JavaScript strings');
if(!pagesBuilder.includes('(?:href|src|action)'))fail('build-pages-preview.mjs','preview builder markup-only rewrite missing');
const contextRouting=fs.readFileSync('core-context.js','utf8');
if(!contextRouting.includes("location.hostname.endsWith('.github.io')")||!contextRouting.includes('const route=routedPath(path)'))fail('core-context.js','GitHub Pages project-path routing missing');
const navRouting=fs.readFileSync('core-nav.js','utf8');
if(!navRouting.includes("location.hostname.endsWith('.github.io')")||!navRouting.includes('const route=routedPath(path)'))fail('core-nav.js','GitHub Pages project-path routing missing');
if(failed)process.exit(1);

const homeSettings=fs.readFileSync('team-settings.html','utf8');if(!homeSettings.includes('Public Links')||!homeSettings.includes('rotate_team_public_token')||!homeSettings.includes('playerPortalLink')||!homeSettings.includes('scoreboardLink')||!homeSettings.includes('calendarLink'))fail('team-settings.html','public link management is missing');if(homeSettings.includes('const settingsPatch={...settings'))fail('team-settings.html','stale settings spread can overwrite rotated public tokens');
if(!homeSettings.includes('id="homeShortcut1"')||!homeSettings.includes('id="homeShortcut2"')||!homeSettings.includes('home_shortcut_1')||!homeSettings.includes('home_shortcut_2'))fail('team-settings.html','Home shortcut settings missing');
if(!home.includes('result-score')||!home.includes('venue-result'))fail('index.html','Home score/venue layout classes missing');
if(!sharedUi.includes('Home polish v6')||!sharedUi.includes('.result-score')||!sharedUi.includes('.hero-match:before'))fail('core-ui.css','Home visual polish missing');
if(failed)process.exit(1);
