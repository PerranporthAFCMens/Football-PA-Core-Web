/* Perranporth Division 1 West: per-team gameweek forecast trajectory.
   Source: https://www.nonleaguematters.co.uk/divisions/320/
   League scores through 14 November 2026 (2026/27), excluding cup matches.
   The V3.1 latest-strength and title-probability snapshot is separate from this
   transparent historical forecast: don't present these as identical algorithms.
   No hard-coded predicted positions or Perranporth-specific weighting. */
(function(global){
"use strict";
const TEAMS=["Holman Sports","Mawnan","Perranporth","Culdrose","Illogan RBL 2nd","Goonhavern","Porthleven 2nd","Lizard Argyle","Newlyn","Probus","Wendron 3rd","Frogpool & Cusgarne","West Cornwall","St Buryan","Falmouth United"];
const RESULTS=[{"date":"2026-08-08","home":"West Cornwall","hg":2,"ag":3,"away":"Holman Sports"},{"date":"2026-08-15","home":"Illogan RBL 2nd","hg":0,"ag":1,"away":"Holman Sports"},{"date":"2026-08-15","home":"West Cornwall","hg":6,"ag":3,"away":"Porthleven 2nd"},{"date":"2026-08-22","home":"Illogan RBL 2nd","hg":2,"ag":4,"away":"Porthleven 2nd"},{"date":"2026-08-22","home":"St Buryan","hg":4,"ag":4,"away":"Goonhavern"},{"date":"2026-08-25","home":"Porthleven 2nd","hg":3,"ag":0,"away":"Lizard Argyle"},{"date":"2026-08-29","home":"Frogpool & Cusgarne","hg":5,"ag":0,"away":"Lizard Argyle"},{"date":"2026-08-29","home":"Newlyn","hg":1,"ag":3,"away":"Goonhavern"},{"date":"2026-08-29","home":"Probus","hg":3,"ag":2,"away":"Porthleven 2nd"},{"date":"2026-08-29","home":"West Cornwall","hg":9,"ag":1,"away":"St Buryan"},{"date":"2026-09-01","home":"Porthleven 2nd","hg":3,"ag":2,"away":"Frogpool & Cusgarne"},{"date":"2026-09-05","home":"Mawnan","hg":6,"ag":0,"away":"Frogpool & Cusgarne"},{"date":"2026-09-05","home":"Probus","hg":0,"ag":3,"away":"Goonhavern"},{"date":"2026-09-12","home":"Lizard Argyle","hg":1,"ag":2,"away":"Holman Sports"},{"date":"2026-09-12","home":"Probus","hg":2,"ag":0,"away":"West Cornwall"},{"date":"2026-09-12","home":"Culdrose","hg":3,"ag":0,"away":"Illogan RBL 2nd"},{"date":"2026-09-12","home":"St Buryan","hg":3,"ag":2,"away":"Frogpool & Cusgarne"},{"date":"2026-09-12","home":"Wendron 3rd","hg":0,"ag":3,"away":"Perranporth"},{"date":"2026-09-19","home":"Illogan RBL 2nd","hg":1,"ag":1,"away":"Newlyn"},{"date":"2026-09-26","home":"Newlyn","hg":3,"ag":4,"away":"Porthleven 2nd"},{"date":"2026-09-26","home":"Probus","hg":1,"ag":3,"away":"Holman Sports"},{"date":"2026-09-26","home":"Culdrose","hg":2,"ag":3,"away":"Perranporth"},{"date":"2026-09-26","home":"St Buryan","hg":4,"ag":5,"away":"Lizard Argyle"},{"date":"2026-09-26","home":"West Cornwall","hg":1,"ag":1,"away":"Falmouth United"},{"date":"2026-10-03","home":"Falmouth United","hg":1,"ag":2,"away":"Lizard Argyle"},{"date":"2026-10-03","home":"Frogpool & Cusgarne","hg":1,"ag":1,"away":"Illogan RBL 2nd"},{"date":"2026-10-03","home":"Goonhavern","hg":1,"ag":4,"away":"Probus"},{"date":"2026-10-03","home":"Holman Sports","hg":6,"ag":0,"away":"Wendron 3rd"},{"date":"2026-10-03","home":"Mawnan","hg":6,"ag":0,"away":"Newlyn"},{"date":"2026-10-03","home":"Culdrose","hg":4,"ag":2,"away":"West Cornwall"},{"date":"2026-10-10","home":"Falmouth United","hg":0,"ag":6,"away":"Perranporth"},{"date":"2026-10-10","home":"Goonhavern","hg":3,"ag":0,"away":"St Buryan"},{"date":"2026-10-10","home":"Mawnan","hg":0,"ag":0,"away":"Lizard Argyle"},{"date":"2026-10-10","home":"Newlyn","hg":3,"ag":1,"away":"Frogpool & Cusgarne"},{"date":"2026-10-10","home":"Porthleven 2nd","hg":1,"ag":5,"away":"Holman Sports"},{"date":"2026-10-10","home":"Probus","hg":2,"ag":2,"away":"Wendron 3rd"},{"date":"2026-10-17","home":"Porthleven 2nd","hg":1,"ag":1,"away":"Perranporth"},{"date":"2026-10-17","home":"Wendron 3rd","hg":0,"ag":4,"away":"Newlyn"},{"date":"2026-10-24","home":"Falmouth United","hg":0,"ag":3,"away":"Wendron 3rd"},{"date":"2026-10-24","home":"Holman Sports","hg":2,"ag":1,"away":"Goonhavern"},{"date":"2026-10-24","home":"Illogan RBL 2nd","hg":2,"ag":1,"away":"Perranporth"},{"date":"2026-10-24","home":"Newlyn","hg":3,"ag":2,"away":"Culdrose"},{"date":"2026-10-31","home":"Falmouth United","hg":0,"ag":0,"away":"Holman Sports"},{"date":"2026-10-31","home":"Frogpool & Cusgarne","hg":4,"ag":4,"away":"Newlyn"},{"date":"2026-10-31","home":"Goonhavern","hg":2,"ag":6,"away":"Culdrose"},{"date":"2026-10-31","home":"Lizard Argyle","hg":2,"ag":4,"away":"Illogan RBL 2nd"},{"date":"2026-10-31","home":"Perranporth","hg":7,"ag":2,"away":"St Buryan"},{"date":"2026-10-31","home":"Wendron 3rd","hg":2,"ag":1,"away":"Probus"},{"date":"2026-10-31","home":"West Cornwall","hg":0,"ag":4,"away":"Mawnan"},{"date":"2026-11-07","home":"Perranporth","hg":1,"ag":1,"away":"Porthleven 2nd"},{"date":"2026-11-07","home":"Probus","hg":0,"ag":1,"away":"Illogan RBL 2nd"},{"date":"2026-11-14","home":"Falmouth United","hg":2,"ag":5,"away":"Illogan RBL 2nd"},{"date":"2026-11-14","home":"Goonhavern","hg":3,"ag":1,"away":"Newlyn"},{"date":"2026-11-14","home":"Holman Sports","hg":0,"ag":1,"away":"Lizard Argyle"},{"date":"2026-11-14","home":"Perranporth","hg":3,"ag":0,"away":"West Cornwall"},{"date":"2026-11-14","home":"Porthleven 2nd","hg":3,"ag":2,"away":"St Buryan"},{"date":"2026-11-14","home":"Culdrose","hg":1,"ag":3,"away":"Frogpool & Cusgarne"},{"date":"2026-11-14","home":"Wendron 3rd","hg":1,"ag":7,"away":"Mawnan"}];
const MATCHES=Object.fromEntries(TEAMS.map(t=>[t,[]]));
RESULTS.forEach((m,i)=>{
 MATCHES[m.home].push({date:m.date,order:i,opponent:m.away,gf:m.hg,ga:m.ag});
 MATCHES[m.away].push({date:m.date,order:i,opponent:m.home,gf:m.ag,ga:m.hg});
});
for(const t of TEAMS)MATCHES[t].sort((a,b)=>a.date.localeCompare(b.date)||a.order-b.order);
function build(){
 const maxGw=Math.max(...TEAMS.map(t=>MATCHES[t].length));
 const trajectory=Object.fromEntries(TEAMS.map(t=>[t,[]]));
 const tables=[];
 for(let gw=1;gw<=maxGw;gw++){
  const stats=Object.fromEntries(TEAMS.map(t=>{
   const played=MATCHES[t].slice(0,gw),p=played.reduce((x,m)=>x+(m.gf>m.ga?3:m.gf===m.ga?1:0),0),gd=played.reduce((x,m)=>x+m.gf-m.ga,0);
   return [t,{played,points:p,gd,ppg:played.length?p/played.length:1.5}];
  }));
  // Three neutral 1.5-PPG prior games stabilise small samples;
  // goal difference is capped so one large win cannot dominate.
  const score=t=>{
   const s=stats[t],n=s.played.length;
   const base=(s.points+4.5)/(n+3);
   const margin=n?Math.max(-2,Math.min(2,s.gd/n)):0;
   const sos=n?s.played.reduce((sum,m)=>sum+stats[m.opponent].ppg,0)/n-1.5:0;
   return base+0.12*margin+0.10*sos;
  };
  const order=[...TEAMS].sort((a,b)=>score(b)-score(a)||stats[b].points-stats[a].points||stats[b].gd-stats[a].gd||a.localeCompare(b));
  const positions=Object.fromEntries(order.map((t,i)=>[t,i+1]));
  // Rank the FULL league uniquely, but only draw a team's nth dot when
  // that team has actually completed at least n league fixtures.
  for(const t of TEAMS)if(MATCHES[t].length>=gw)trajectory[t].push([gw,positions[t]]);
  if(new Set(Object.values(positions)).size!==TEAMS.length)throw Error("Duplicate predicted finishing position at GW"+gw);
  tables.push({gw,order,positions});
 }
 return {maxGw,teams:TEAMS.map(t=>[t,trajectory[t]]),tables,sourceMatches:RESULTS.length,asOf:"14 Nov 2026",method:"Smoothed points per game + capped goal difference + opponent strength; same formula for every club"};
}
global.LeagueTrajectory=Object.freeze({build});
})(window);
