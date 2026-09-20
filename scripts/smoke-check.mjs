import fs from 'node:fs';

const pages=[
  'index.html','players.html','match-centre.html','team-settings.html',
  'fixture-sync.html','voting.html','subs.html','player-portal.html'
];
let failed=false;
const fail=(file,msg)=>{failed=true;console.error(`FAIL ${file}: ${msg}`)};

for(const file of pages){
  const html=fs.readFileSync(file,'utf8');

  const ids=[...html.matchAll(/\bid=["']([^"']+)["']/g)].map(m=>m[1]);
  const seen=new Set();
  for(const id of ids){if(seen.has(id))fail(file,`duplicate id "${id}"`);seen.add(id)}

  const refs=[...html.matchAll(/\$\('([^']+)'\)/g)].map(m=>m[1]);
  for(const id of new Set(refs)){if(!seen.has(id))fail(file,`JavaScript references missing element #${id}`)}

  for(const m of html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/gi)){
    try{new Function(m[1])}catch(e){fail(file,`inline JavaScript syntax error: ${e.message}`)}
  }

  if(!html.includes('/core-ui.css'))fail(file,'missing shared /core-ui.css');
  if(!html.includes('/core-nav.js'))fail(file,'missing shared /core-nav.js');

  const visible=html
    .replace(/<script[\s\S]*?<\/script>/gi,' ')
    .replace(/<style[\s\S]*?<\/style>/gi,' ')
    .replace(/<[^>]+>/g,' ')
    .replace(/\s+/g,' ');
  for(const phrase of ['Saved to Supabase','Synced from Supabase','Core test','browser-only','secure Dev access']){
    if(visible.toLowerCase().includes(phrase.toLowerCase()))fail(file,`customer-facing debug wording: "${phrase}"`);
  }
  if(/Club_Logo\.png/i.test(html))fail(file,'hardcoded club logo found');
}

const match=fs.readFileSync('match-centre.html','utf8');
if(/45\s*\*\s*60|90\s*\*\s*60/.test(match))fail('match-centre.html','hardcoded 45/90 minute match timing found');
if(/\.from\(['"]players['"]\)[\s\S]{0,250}\.eq\(['"]club_id['"]/.test(match))fail('match-centre.html','loads club-wide players instead of team_players');

if(failed)process.exit(1);
console.log('Football PA Core smoke checks passed.');
