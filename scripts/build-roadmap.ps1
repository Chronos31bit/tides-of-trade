# build-roadmap.ps1 — generates a self-contained tides-roadmap.html from the codebase-audit JSON.
# One-shot: reads the audit workflow output, curates/merges nodes, emits a clickable copy-prompt roadmap.
# Re-run after a fresh audit by updating $AuditPath.

param(
  [string]$AuditPath = "C:\Users\derin\AppData\Local\Temp\claude\C--Users-derin-Documents-tides-of-trade\d9382a63-b1cf-4507-a2e5-b4b25f8804ca\tasks\wuxbau472.output",
  [string]$OutPath   = "C:\Users\derin\Documents\tides-of-trade\tides-roadmap.html",
  [string]$Synced    = "June 1, 2026"
)

if (-not (Test-Path $AuditPath)) { throw "Audit file not found: $AuditPath" }

# Read as UTF-8 — the audit .output is UTF-8; PS5.1's default ANSI read mangles em-dashes into mojibake.
$result = (Get-Content $AuditPath -Raw -Encoding UTF8 | ConvertFrom-Json).result

# --- curation manifest ---
# worldfx-harborevent-print is a duplicate of worldfx-debug-leak (same residual print at WorldFXController:963) — drop it.
$drop = 'cast-miss-toast','emote-whitelist-in-config','streak-cosmetics','offline-payout-wiring','cosmetic-catalog','worldfx-harborevent-print'
# Lanes/priorities now come straight from the audit nodes (each node carries an explicit `lane`); no overrides needed.
$laneOverride = @{}
$priOverride  = @{}
$nameOverride = @{}

function Get-Lane($status) { switch ($status) { 'done' { 'shipped' } default { $status } } }

$out = New-Object System.Collections.Generic.List[object]
foreach ($n in $result.nodes) {
  if ($drop -contains $n.id) { continue }
  # Lane precedence: explicit override > explicit lane from audit JSON > derived from status.
  $lane = if ($laneOverride.ContainsKey($n.id)) { $laneOverride[$n.id] }
          elseif ($n.PSObject.Properties.Name -contains 'lane' -and $n.lane) { $n.lane }
          else { Get-Lane $n.status }
  $pri  = if ($priOverride.ContainsKey($n.id))  { $priOverride[$n.id]  } else { $n.priority }
  $nm   = if ($nameOverride.ContainsKey($n.id)) { $nameOverride[$n.id] } else { $n.name }
  $deps = @($n.deps | ForEach-Object { if ($_ -eq 'cosmetic-catalog') { 'cosmetics-catalog' } else { $_ } })
  $out.Add([ordered]@{
    id       = $n.id
    name     = $nm
    sub      = $n.sub
    status   = $n.status
    priority = $pri
    lane     = $lane
    pillars  = @($n.pillars)
    deps     = $deps
    evidence = @($n.evidence)
    notes    = $n.notes
    prompt   = $n.prompt
  })
}

$json = $out | ConvertTo-Json -Depth 6
# ConvertTo-Json collapses a single-item array; not our case (~40 nodes), but guard anyway:
if ($json[0] -ne '[') { $json = "[$json]" }

$tpl = @'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Tides of Trade - Build Roadmap</title>
<style>
:root{--bg:#0a1322;--ink:#e9eff8;--muted:#8aa0c0;--panel:#111d34;--panel2:#19284a;--line:#2a3a63;
--done:#22c55e;--wip:#f59e0b;--critical:#ef4444;--next:#60a5fa;--polish:#a78bfa;--launch:#f97316;--backlog:#94a3b8;--accent:#7dd3fc;}
*{box-sizing:border-box;margin:0;padding:0}
body{background:var(--bg);color:var(--ink);font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;padding:22px 20px 90px;max-width:1400px;margin:0 auto}
h1{font-size:22px;letter-spacing:-.4px}
.sub{color:var(--muted);font-size:13px;margin-top:6px;max-width:860px;line-height:1.55}
.sub b{color:var(--ink)}.synced{color:var(--done);font-weight:600}
.summary{display:flex;flex-wrap:wrap;gap:9px;margin-top:16px}
.stat{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:8px 13px;min-width:90px;cursor:pointer}
.stat .v{font-size:19px;font-weight:700}.stat .l{font-size:10px;color:var(--muted);text-transform:uppercase;letter-spacing:.5px}
.stat.critical .v{color:var(--critical)}.stat.wip .v{color:var(--wip)}.stat.next .v{color:var(--next)}.stat.polish .v{color:var(--polish)}.stat.launch .v{color:var(--launch)}.stat.backlog .v{color:var(--backlog)}.stat.shipped .v{color:var(--done)}
.controls{display:flex;flex-wrap:wrap;gap:8px;margin:18px 0 4px;align-items:center}
.pill{background:var(--panel);border:1px solid var(--line);color:var(--muted);font-size:11px;font-weight:600;padding:6px 12px;border-radius:20px;cursor:pointer}
.pill.on{background:rgba(125,211,252,.14);border-color:var(--accent);color:var(--accent)}
.search{flex:1;max-width:240px;background:var(--panel);border:1px solid var(--line);color:var(--ink);font-size:12px;padding:8px 12px;border-radius:20px;outline:none}
section.lane,details.lane{margin-top:24px}
.lane-h{display:flex;align-items:center;gap:10px;font-size:13px;font-weight:700;letter-spacing:.3px;padding-bottom:8px;border-bottom:1px solid var(--line);cursor:default}
details.lane>summary{list-style:none}details.lane>summary::-webkit-details-marker{display:none}
details.lane>summary .lane-h{cursor:pointer}
.lane-h .cnt{font-size:11px;color:var(--muted);font-weight:600}
.lane-h .chev{font-size:11px;color:var(--muted);transition:transform .15s}
details.lane[open]>summary .chev{transform:rotate(90deg)}
.l-critical .lane-h{color:var(--critical)}.l-wip .lane-h{color:var(--wip)}.l-next .lane-h{color:var(--next)}.l-polish .lane-h{color:var(--polish)}.l-launch .lane-h{color:var(--launch)}.l-backlog .lane-h{color:var(--backlog)}.l-shipped .lane-h{color:var(--done)}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(248px,1fr));gap:10px;margin-top:12px}
.card{text-align:left;background:var(--panel);border:1px solid var(--line);border-left-width:3px;border-radius:10px;padding:11px 12px;cursor:pointer;color:var(--ink);font:inherit;transition:transform .12s,border-color .12s}
.card:hover{transform:translateY(-2px);border-color:var(--accent)}
.card.b-critical{border-left-color:var(--critical)}.card.b-wip{border-left-color:var(--wip)}.card.b-next{border-left-color:var(--next)}.card.b-polish{border-left-color:var(--polish)}.card.b-launch{border-left-color:var(--launch)}.card.b-backlog{border-left-color:var(--backlog)}.card.b-shipped{border-left-color:var(--done)}
.card .cn{font-size:13px;font-weight:700;display:flex;justify-content:space-between;gap:8px;align-items:baseline}
.card .pr{font-size:9px;font-weight:800;padding:1px 6px;border-radius:8px;background:var(--panel2);border:1px solid var(--line);color:var(--muted);flex-shrink:0}
.pr.P0{color:var(--critical);border-color:var(--critical)}.pr.P1{color:var(--launch)}.pr.P2{color:var(--next)}.pr.P3{color:var(--backlog)}.pr.DONE{color:var(--done)}
.card .cs{font-size:11px;color:var(--muted);margin-top:4px;line-height:1.4}
.hidden{display:none!important}
.scrim{position:fixed;inset:0;background:rgba(2,6,18,.82);display:none;align-items:flex-start;justify-content:center;padding:22px 14px;z-index:50;overflow:auto;backdrop-filter:blur(4px)}
.scrim.on{display:flex}
.modal{position:relative;background:var(--panel);border:1px solid var(--line);border-radius:14px;max-width:800px;width:100%;margin:auto}
.mh{padding:18px 44px 12px 20px;border-bottom:1px solid var(--line)}
.mh .tt{font-size:18px;font-weight:700;line-height:1.3}
.mh .chips{display:flex;flex-wrap:wrap;gap:6px;margin-top:9px}
.chip{font-size:10px;font-weight:700;padding:3px 8px;border-radius:9px;border:1px solid var(--line);background:var(--panel2);color:var(--muted);text-transform:uppercase;letter-spacing:.3px}
.chip.s-critical{color:var(--critical);border-color:var(--critical)}.chip.s-wip{color:var(--wip)}.chip.s-next{color:var(--next)}.chip.s-polish{color:var(--polish)}.chip.s-launch{color:var(--launch)}.chip.s-backlog{color:var(--backlog)}.chip.s-done{color:var(--done)}
.mb{padding:16px 20px 20px}
.mb h4{font-size:10px;letter-spacing:1.2px;text-transform:uppercase;color:var(--muted);margin:16px 0 6px}.mb h4:first-child{margin-top:0}
.mb p{font-size:13px;line-height:1.6}
.mb ul{margin:4px 0 0 16px;font-size:12px;line-height:1.55;color:var(--muted)}
.mb ul li{margin-bottom:3px}
.mb code,.mb li{font-family:inherit}
.promptbox{background:#06101f;border:1px solid var(--line);border-radius:10px;padding:13px;font-family:ui-monospace,Consolas,monospace;font-size:12px;line-height:1.55;color:#cfe2ff;white-space:pre-wrap;word-wrap:break-word;max-height:440px;overflow:auto;margin-top:6px}
.row{display:flex;gap:8px;margin-top:12px;align-items:center;flex-wrap:wrap}
.btn{background:var(--accent);color:#062136;border:0;border-radius:9px;padding:9px 16px;font-size:12px;font-weight:700;cursor:pointer}
.btn:hover{filter:brightness(1.08)}
.btn.ghost{background:var(--panel2);color:var(--ink);border:1px solid var(--line)}
.ok{font-size:11px;color:var(--done);font-weight:600;opacity:0;transition:opacity .2s}.ok.on{opacity:1}
.close{position:absolute;top:12px;right:14px;background:transparent;border:0;color:var(--muted);font-size:26px;line-height:1;cursor:pointer}.close:hover{color:var(--ink)}
.shipnote{font-size:13px;color:var(--done);font-weight:600}
@media(max-width:560px){.grid{grid-template-columns:1fr}body{padding:18px 14px 80px}}
</style>
</head>
<body>
<h1>Tides of Trade - Build Roadmap</h1>
<p class="sub">Prioritized from a full codebase audit. <b>Click any card</b> -&gt; read status + evidence -&gt; <b>Copy Prompt</b> -&gt; paste into Claude Code. Every prompt is grounded in real <code>file:line</code> references and prepends the CLAUDE.md guardrails. <span class="synced">Last synced with code: @@SYNCED@@</span></p>
<div class="summary" id="summary"></div>
<div class="controls">
  <button class="pill on" data-f="all">All</button>
  <button class="pill" data-f="critical">Launch Blockers</button>
  <button class="pill" data-f="wip">In progress</button>
  <button class="pill" data-f="next">Next</button>
  <button class="pill" data-f="polish">Polish</button>
  <button class="pill" data-f="launch">Pre-launch</button>
  <button class="pill" data-f="backlog">Backlog</button>
  <button class="pill" data-f="shipped">Shipped</button>
  <input id="search" class="search" placeholder="Search nodes...">
</div>
<div id="board"></div>
<div class="scrim" id="scrim"><div class="modal" id="modal"></div></div>

<script id="nodes" type="application/json">@@NODES@@</script>
<script>
const RAW = JSON.parse(document.getElementById('nodes').textContent);
const PREAMBLE = "Read CLAUDE.md first. Per CLAUDE.md: server-authoritative (client requests, server validates - never client-decided catches/prices/tiers); all tunables in GameConfig (no magic numbers); Knit services/controllers with Trove cleanup; TweenService routed through MotionUtil (ReducedMotion-safe, never Heartbeat for UI motion); UIKit/UIUtil for chrome (no inline Color3/font/spacing); mobile-first 380px portrait (44px min hit targets, >=12px font); additive ProfileService schema only (never bump TidesProfile_v1 - stable IDs are forever); cozy tone (no FOMO, no combat, no progress-loss, no flashing >3Hz, cosmetic/QoL monetization only, text-only NPCs). Git: branch feat/<name>, commit often, merge --no-ff.\n\n";
const LANES = [
  {key:'critical', label:'🚨 Launch Blockers (P0)', cls:'l-critical'},
  {key:'wip',      label:'Finish In-Flight',                cls:'l-wip'},
  {key:'next',     label:'Next Features',                   cls:'l-next'},
  {key:'polish',   label:'Polish & Juice',                  cls:'l-polish'},
  {key:'launch',   label:'Pre-Launch · Monetization',  cls:'l-launch'},
  {key:'backlog',  label:'Backlog / Discovery',             cls:'l-backlog'},
  {key:'shipped',  label:'Shipped (context)',               cls:'l-shipped', collapsed:true},
];
const PR = {P0:0,P1:1,P2:2,P3:3,DONE:9};
const byId = {};
RAW.forEach(n => byId[n.id] = n);
const esc = s => String(s==null?'':s).replace(/[&<>]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));

// summary tiles
const counts = {};
LANES.forEach(l => counts[l.key] = RAW.filter(n => n.lane===l.key).length);
const sumEl = document.getElementById('summary');
sumEl.innerHTML = LANES.map(l =>
  '<div class="stat '+l.key+'" data-f="'+l.key+'"><div class="v">'+counts[l.key]+'</div><div class="l">'+l.label.replace(/🚨 /,'').replace(/ \(P0\)/,'')+'</div></div>'
).join('');

// board
const board = document.getElementById('board');
function cardHtml(n){
  return '<button class="card b-'+n.lane+'" data-id="'+n.id+'">'
    + '<div class="cn"><span>'+esc(n.name)+'</span><span class="pr '+n.priority+'">'+n.priority+'</span></div>'
    + '<div class="cs">'+esc(n.sub)+'</div></button>';
}
board.innerHTML = LANES.map(l => {
  const nodes = RAW.filter(n => n.lane===l.key).sort((a,b)=>(PR[a.priority]??5)-(PR[b.priority]??5));
  if(!nodes.length) return '';
  const head = '<div class="lane-h">'+(l.collapsed?'<span class="chev">▶</span>':'')+'<span>'+l.label+'</span><span class="cnt">'+nodes.length+'</span></div>';
  const grid = '<div class="grid">'+nodes.map(cardHtml).join('')+'</div>';
  if(l.collapsed) return '<details class="lane '+l.cls+'" data-lane="'+l.key+'"><summary>'+head+'</summary>'+grid+'</details>';
  return '<section class="lane '+l.cls+'" data-lane="'+l.key+'">'+head+grid+'</section>';
}).join('');

// modal
const scrim = document.getElementById('scrim');
const modal = document.getElementById('modal');
let curPrompt = '';
function openNode(id){
  const n = byId[id]; if(!n) return;
  const sChip = n.status==='done' ? 'done' : n.status;
  let html = '<button class="close" aria-label="Close">×</button>';
  html += '<div class="mh"><div class="tt">'+esc(n.name)+'</div><div class="chips">'
        + '<span class="chip s-'+sChip+'">'+n.status+'</span>'
        + '<span class="chip">'+n.priority+'</span>'
        + (n.pillars||[]).map(p=>'<span class="chip">'+esc(p)+'</span>').join('')
        + '</div></div><div class="mb">';
  html += '<h4>Status / why</h4><p>'+esc(n.notes)+'</p>';
  if(n.deps && n.deps.length){
    html += '<h4>Depends on</h4><ul>'+n.deps.map(d=>'<li>'+esc(byId[d]?byId[d].name:d)+'</li>').join('')+'</ul>';
  }
  if(n.evidence && n.evidence.length){
    html += '<h4>Evidence</h4><ul>'+n.evidence.map(e=>'<li>'+esc(e)+'</li>').join('')+'</ul>';
  }
  if(n.prompt && n.prompt.trim().length){
    curPrompt = PREAMBLE + n.prompt;
    html += '<h4>Claude Code prompt</h4><div class="promptbox">'+esc(curPrompt)+'</div>'
          + '<div class="row"><button class="btn" id="copyBtn">Copy Prompt</button>'
          + '<button class="btn ghost" id="closeBtn2">Close</button>'
          + '<span class="ok" id="okMsg">Copied to clipboard</span></div>';
  } else {
    curPrompt = '';
    html += '<p class="shipnote">✅ Shipped - no action needed. Evidence above is for context.</p>';
  }
  html += '</div>';
  modal.innerHTML = html;
  scrim.classList.add('on');
  const cb = document.getElementById('copyBtn');
  if(cb) cb.onclick = () => {
    navigator.clipboard.writeText(curPrompt).then(()=>{
      const ok=document.getElementById('okMsg'); ok.classList.add('on'); setTimeout(()=>ok.classList.remove('on'),1800);
    }).catch(()=>{
      const ta=document.createElement('textarea'); ta.value=curPrompt; ta.style.cssText='position:fixed;opacity:0';
      document.body.appendChild(ta); ta.select(); document.execCommand('copy'); document.body.removeChild(ta);
      const ok=document.getElementById('okMsg'); ok.classList.add('on'); setTimeout(()=>ok.classList.remove('on'),1800);
    });
  };
  const c2 = document.getElementById('closeBtn2'); if(c2) c2.onclick = closeModal;
  modal.querySelector('.close').onclick = closeModal;
}
function closeModal(){ scrim.classList.remove('on'); }
scrim.onclick = e => { if(e.target===scrim) closeModal(); };
document.addEventListener('keydown', e => { if(e.key==='Escape') closeModal(); });
board.addEventListener('click', e => { const c=e.target.closest('.card'); if(c) openNode(c.dataset.id); });

// filter + search
let activeFilter='all', q='';
function applyFilter(){
  document.querySelectorAll('[data-lane]').forEach(sec => {
    const lane = sec.dataset.lane;
    let anyVisible=false;
    sec.querySelectorAll('.card').forEach(card => {
      const n = byId[card.dataset.id];
      const laneOk = activeFilter==='all' || activeFilter===lane;
      const text = (n.name+' '+n.sub+' '+n.notes+' '+n.id).toLowerCase();
      const qOk = !q || text.includes(q);
      const show = laneOk && qOk;
      card.classList.toggle('hidden', !show);
      if(show) anyVisible=true;
    });
    sec.classList.toggle('hidden', !anyVisible);
    if(sec.tagName==='DETAILS' && (q || activeFilter==='shipped')) sec.open = anyVisible;
  });
}
document.querySelectorAll('.pill').forEach(p => p.onclick = () => {
  document.querySelectorAll('.pill').forEach(x=>x.classList.remove('on'));
  p.classList.add('on'); activeFilter=p.dataset.f; applyFilter();
});
sumEl.querySelectorAll('.stat').forEach(s => s.onclick = () => {
  const f=s.dataset.f; const pill=document.querySelector('.pill[data-f="'+f+'"]');
  if(pill) pill.click();
});
document.getElementById('search').addEventListener('input', e => { q=e.target.value.trim().toLowerCase(); applyFilter(); });
</script>
</body>
</html>
'@

$html = $tpl.Replace('@@NODES@@', $json).Replace('@@SYNCED@@', $Synced)
[System.IO.File]::WriteAllText($OutPath, $html, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "Wrote $OutPath"
Write-Host ("Nodes: {0}" -f $out.Count)
$out | Group-Object lane | Sort-Object Name | ForEach-Object { Write-Host ("  {0}: {1}" -f $_.Name, $_.Count) }
