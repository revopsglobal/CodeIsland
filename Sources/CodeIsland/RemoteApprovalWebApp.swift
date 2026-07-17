import Foundation

enum RemoteApprovalWebApp {
    static let manifest = #"""
    {
      "name": "CodeIsland Personal Hub",
      "short_name": "CodeIsland",
      "start_url": "/",
      "display": "standalone",
      "background_color": "#070a08",
      "theme_color": "#101611",
      "icons": []
    }
    """#

    static let serviceWorker = #"""
    const CACHE = 'codeisland-personal-hub-v2';
    self.addEventListener('install', event => {
      event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(['/'])));
      self.skipWaiting();
    });
    self.addEventListener('activate', event => event.waitUntil(self.clients.claim()));
    self.addEventListener('fetch', event => {
      const url = new URL(event.request.url);
      if (url.pathname.startsWith('/api/')) return;
      event.respondWith(fetch(event.request).catch(() => caches.match(event.request)));
    });
    """#

    static let html = #"""
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
      <meta name="theme-color" content="#101611">
      <meta name="apple-mobile-web-app-capable" content="yes">
      <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
      <meta name="apple-mobile-web-app-title" content="CodeIsland">
      <link rel="manifest" href="/manifest.webmanifest">
      <title>CodeIsland Personal Hub</title>
      <style>
        :root { color-scheme: dark; --green:#4dd96b; --amber:#ffb347; --red:#ff5f64; --muted:#8d9b90; }
        * { box-sizing:border-box; }
        body { margin:0; min-height:100vh; background:radial-gradient(circle at top,#17231a 0,#090d0a 38%,#050706 100%); color:#f4f7f4; font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif; }
        main { width:min(680px,100%); margin:0 auto; padding:max(22px,env(safe-area-inset-top)) 16px max(28px,env(safe-area-inset-bottom)); }
        header { display:flex; align-items:center; gap:12px; margin-bottom:18px; }
        .mark { width:44px; height:30px; border-radius:13px 13px 9px 9px; background:#020302; box-shadow:0 0 0 1px #273128,0 12px 32px #0008; position:relative; }
        .mark:after { content:""; position:absolute; left:9px; right:9px; bottom:7px; height:4px; border-radius:3px; background:var(--green); box-shadow:0 0 12px #4dd96baa; }
        h1 { font-size:20px; margin:0; letter-spacing:-.02em; }
        .subtitle,.muted { color:var(--muted); font-size:13px; }
        .status { margin-left:auto; display:flex; align-items:center; gap:7px; font-size:12px; color:var(--muted); }
        .dot { width:8px; height:8px; border-radius:50%; background:#657067; }
        .dot.live { background:var(--green); box-shadow:0 0 10px #4dd96b99; }
        .card { border:1px solid #263028; background:linear-gradient(145deg,#131915,#0d120f); border-radius:18px; padding:16px; margin:12px 0; box-shadow:0 16px 48px #0005; }
        .approval { border-color:#6e542c; }
        .eyebrow { color:var(--amber); font:700 11px ui-monospace,SFMono-Regular,Menlo,monospace; text-transform:uppercase; letter-spacing:.08em; }
        .tool { font-size:19px; font-weight:750; margin:8px 0 4px; overflow-wrap:anywhere; }
        .meta { display:flex; flex-wrap:wrap; gap:7px; margin:8px 0 12px; }
        .chip { padding:5px 8px; border-radius:8px; background:#ffffff0d; color:#b8c2ba; font:600 11px ui-monospace,SFMono-Regular,Menlo,monospace; }
        .detail { white-space:pre-wrap; overflow-wrap:anywhere; color:#d7ddd8; font:13px/1.45 ui-monospace,SFMono-Regular,Menlo,monospace; background:#050806; border-radius:11px; padding:11px; max-height:240px; overflow:auto; }
        .actions { display:grid; grid-template-columns:1fr 1.3fr; gap:10px; margin-top:14px; }
        button { border:0; border-radius:12px; min-height:48px; padding:0 14px; font-size:15px; font-weight:750; cursor:pointer; }
        button:disabled { opacity:.45; }
        .deny { background:#351517; color:#ffbec0; box-shadow:inset 0 0 0 1px #6c2b30; }
        .approve { background:var(--green); color:#061008; }
        .secondary { background:#1a221c; color:#dce3dd; box-shadow:inset 0 0 0 1px #344037; }
        input { width:100%; min-height:50px; border:1px solid #344037; border-radius:12px; padding:0 13px; color:#f4f7f4; background:#080c09; font-size:16px; outline:none; }
        input:focus { border-color:var(--green); box-shadow:0 0 0 3px #4dd96b22; }
        label { display:block; color:#aeb8b0; font-size:12px; font-weight:650; margin:12px 0 6px; }
        .empty { text-align:center; padding:34px 18px; }
        .empty strong { display:block; font-size:17px; margin-bottom:6px; }
        .modes { display:grid; grid-template-columns:repeat(4,1fr); gap:6px; margin:0 0 12px; }
        .mode { min-height:38px; border-radius:10px; background:#141a16; color:#8d9b90; font:750 11px ui-monospace,SFMono-Regular,Menlo,monospace; text-transform:uppercase; }
        .mode.active { background:var(--amber); color:#171006; }
        .section-title { margin:18px 2px 8px; color:#9daa9f; font:750 11px ui-monospace,SFMono-Regular,Menlo,monospace; text-transform:uppercase; letter-spacing:.12em; }
        .module-grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(260px,1fr)); gap:10px; }
        .module { border:1px solid #29312b; background:#0e1310; border-radius:15px; padding:13px; }
        .module-head { display:flex; align-items:flex-start; gap:9px; }
        .module-title { font-size:15px; font-weight:750; }
        .module-summary { margin-top:3px; color:#8d9b90; font-size:12px; line-height:1.35; }
        .availability { margin-left:auto; color:var(--amber); font:750 9px ui-monospace,SFMono-Regular,Menlo,monospace; text-transform:uppercase; }
        .hub-item { margin-top:8px; padding:9px; border-radius:10px; background:#050806; }
        .hub-item-title { font-size:12px; font-weight:700; overflow-wrap:anywhere; }
        .hub-item-subtitle { margin-top:2px; color:#78847a; font-size:10px; }
        .hub-actions { display:flex; flex-wrap:wrap; gap:6px; margin-top:8px; }
        .hub-action { min-height:34px; padding:0 10px; border-radius:9px; background:#1b241e; color:#dce3dd; font-size:11px; box-shadow:inset 0 0 0 1px #344037; }
        .hub-action.primary { background:var(--amber); color:#171006; box-shadow:none; }
        progress { width:100%; height:5px; margin-top:7px; accent-color:var(--amber); }
        .hidden { display:none !important; }
        #error { color:#ff9da0; font-size:13px; margin-top:10px; white-space:pre-wrap; }
        footer { text-align:center; color:#657067; font-size:11px; padding:18px 0; }
      </style>
    </head>
    <body>
      <main>
        <header>
          <div class="mark" aria-hidden="true"></div>
          <div><h1>CodeIsland</h1><div class="subtitle">Private personal hub</div></div>
          <div class="status"><span id="dot" class="dot"></span><span id="status">Connecting</span></div>
        </header>

        <section id="pair" class="card hidden">
          <div class="eyebrow">Pair this iPhone</div>
          <div class="tool">Connect to your Mac</div>
          <p class="muted">Open CodeIsland Settings → Buddy on the Mac and enter the six-digit code. The code expires after ten minutes.</p>
          <label for="code">Pairing code</label>
          <input id="code" inputmode="numeric" autocomplete="one-time-code" maxlength="6" placeholder="000000">
          <label for="name">Device name</label>
          <input id="name" autocomplete="name" value="Greg's iPhone">
          <div class="actions" style="grid-template-columns:1fr">
            <button id="pairButton" class="approve">Pair securely</button>
          </div>
          <div id="error"></div>
        </section>

        <nav id="modes" class="modes hidden" aria-label="Hub mode">
          <button class="mode" data-mode="auto">Auto</button>
          <button class="mode" data-mode="home">Home</button>
          <button class="mode" data-mode="work">Work</button>
          <button class="mode" data-mode="code">Code</button>
        </nav>
        <div id="hubTitle" class="section-title hidden">Personal hub</div>
        <section id="hub" class="module-grid"></section>
        <div id="approvalTitle" class="section-title hidden">Agent approvals</div>
        <section id="approvals"></section>
        <section id="empty" class="card empty hidden">
          <strong>No approvals waiting</strong>
          <span class="muted">This page checks the Mac every four seconds.</span>
        </section>
        <footer>Tailnet-only · exact-request validation · single-use actions</footer>
      </main>
      <script>
        const tokenKey = 'codeisland.remote.deviceToken.v1';
        const modeKey = 'codeisland.hub.mode.v1';
        let deviceToken = localStorage.getItem(tokenKey) || '';
        let selectedMode = localStorage.getItem(modeKey) || 'auto';
        let busy = new Set();
        const pair = document.getElementById('pair');
        const approvals = document.getElementById('approvals');
        const empty = document.getElementById('empty');
        const status = document.getElementById('status');
        const dot = document.getElementById('dot');
        const errorBox = document.getElementById('error');
        const modes = document.getElementById('modes');
        const hub = document.getElementById('hub');
        const hubTitle = document.getElementById('hubTitle');
        const approvalTitle = document.getElementById('approvalTitle');

        const moduleNames = {
          nowPlaying:'Now Playing',shelf:'Shelf',calendar:'Calendar',reminders:'Tasks',notes:'Notes',
          system:'System',weather:'Weather',notifications:'Notifications',claude:'Claude',agents:'Agents',
          github:'GitHub',audio:'Audio',bluetooth:'Bluetooth',battery:'Battery',quickToggles:'Quick Toggles',
          downloads:'Downloads',camera:'Camera',teleprompter:'Prompter',windowManager:'Windows'
        };

        function authHeaders() { return { 'Authorization': `Bearer ${deviceToken}` }; }
        function setStatus(text, live=false) { status.textContent=text; dot.classList.toggle('live',live); }
        function escapeHTML(value='') { const e=document.createElement('div'); e.textContent=value; return e.innerHTML; }
        function relativeTime(value) {
          const seconds=Math.max(0,Math.round((Date.now()-new Date(value).getTime())/1000));
          if(seconds<60) return `${seconds}s ago`; if(seconds<3600) return `${Math.floor(seconds/60)}m ago`; return `${Math.floor(seconds/3600)}h ago`;
        }

        async function pairDevice() {
          errorBox.textContent='';
          const button=document.getElementById('pairButton'); button.disabled=true;
          try {
            const response=await fetch('/api/pair',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({code:document.getElementById('code').value,deviceName:document.getElementById('name').value})});
            const body=await response.json();
            if(!response.ok) throw new Error(body.error||'Pairing failed');
            deviceToken=body.deviceToken; localStorage.setItem(tokenKey,deviceToken); pair.classList.add('hidden'); await refresh();
          } catch(error) { errorBox.textContent=error.message; }
          finally { button.disabled=false; }
        }

        async function decide(id, actionToken, decision) {
          if(busy.has(id)) return;
          const verb=decision==='approve'?'Approve':'Deny';
          if(!confirm(`${verb} this exact request?`)) return;
          busy.add(id); renderLast();
          try {
            const response=await fetch(`/api/approvals/${encodeURIComponent(id)}/decision`,{method:'POST',headers:{...authHeaders(),'Content-Type':'application/json'},body:JSON.stringify({decision,actionToken})});
            const body=await response.json();
            if(!response.ok) throw new Error(body.error||'Decision failed');
            await refresh();
          } catch(error) { alert(error.message); await refresh(); }
          finally { busy.delete(id); }
        }

        let lastItems=[];
        function render(items) {
          lastItems=items; renderLast();
        }
        function renderLast() {
          approvals.innerHTML=lastItems.map(item=>`<article class="card approval">
            <div class="eyebrow">${escapeHTML(item.source)} · ${relativeTime(item.createdAt)}</div>
            <div class="tool">${escapeHTML(item.tool)}</div>
            <div class="meta"><span class="chip">${escapeHTML(item.workspace||'Session')}</span><span class="chip">#${escapeHTML(item.sessionId.slice(-8))}</span></div>
            ${item.detail?`<div class="detail">${escapeHTML(item.detail)}</div>`:''}
            <div class="actions">
              <button class="deny" ${busy.has(item.id)?'disabled':''} data-id="${escapeHTML(item.id)}" data-token="${escapeHTML(item.actionToken)}" data-decision="deny">Deny</button>
              <button class="approve" ${busy.has(item.id)?'disabled':''} data-id="${escapeHTML(item.id)}" data-token="${escapeHTML(item.actionToken)}" data-decision="approve">Approve once</button>
            </div>
          </article>`).join('');
          approvals.querySelectorAll('button[data-decision]').forEach(button=>button.addEventListener('click',()=>decide(button.dataset.id,button.dataset.token,button.dataset.decision)));
          empty.classList.toggle('hidden',lastItems.length!==0);
          approvalTitle.classList.toggle('hidden',lastItems.length===0);
        }

        function renderHub(snapshot) {
          hubTitle.textContent=`${snapshot.resolvedMode.toUpperCase()} · ${snapshot.serverName}`;
          hubTitle.classList.remove('hidden'); modes.classList.remove('hidden');
          modes.querySelectorAll('[data-mode]').forEach(button=>button.classList.toggle('active',button.dataset.mode===selectedMode));
          hub.innerHTML=(snapshot.modules||[]).map(module=>`<article class="module">
            <div class="module-head"><div><div class="module-title">${escapeHTML(moduleNames[module.id]||module.id)}</div><div class="module-summary">${escapeHTML(module.summary||'')}</div></div><div class="availability">${escapeHTML(module.availability)}</div></div>
            ${(module.items||[]).map(item=>`<div class="hub-item"><div class="hub-item-title">${escapeHTML(item.title)}</div>${item.subtitle?`<div class="hub-item-subtitle">${escapeHTML(item.subtitle)}</div>`:''}${item.progress!==null&&item.progress!==undefined?`<progress value="${Number(item.progress)}" max="1"></progress>`:''}${renderHubActions(module.id,item.actions||[],item.id,item.detail||'')}</div>`).join('')}
            ${renderHubActions(module.id,module.actions||[],null,'')}
          </article>`).join('');
          hub.querySelectorAll('[data-hub-action]').forEach(button=>button.addEventListener('click',()=>runHubAction(button.dataset.module,button.dataset.action,button.dataset.target||null,button.dataset.deeplink||null,button.dataset.payload||'')));
        }

        function renderHubActions(moduleID,actions,targetID,payload) {
          if(!actions.length) return '';
          return `<div class="hub-actions">${actions.map(action=>`<button class="hub-action ${action.role==='primary'?'primary':''}" data-hub-action="1" data-module="${escapeHTML(moduleID)}" data-action="${escapeHTML(action.id)}" data-target="${escapeHTML(action.targetID||targetID||'')}" data-deeplink="${escapeHTML(action.deepLink||'')}" data-payload="${escapeHTML(payload)}">${escapeHTML(action.label)}</button>`).join('')}</div>`;
        }

        async function runHubAction(moduleID,actionID,targetID,deepLink,payload) {
          if(actionID==='copyToDevice') {
            try { await navigator.clipboard.writeText(payload); alert('Copied to this device'); }
            catch(error) { alert('Clipboard permission was denied'); }
            return;
          }
          if(deepLink) { window.location.href=deepLink; return; }
          let value=null;
          if((moduleID==='reminders'||moduleID==='notes')&&actionID==='add') {
            value=prompt(moduleID==='notes'?'New note':'New task'); if(!value||!value.trim()) return; value=value.trim();
          }
          try {
            const preparedResponse=await fetch('/api/hub/actions/prepare',{method:'POST',headers:{...authHeaders(),'Content-Type':'application/json'},body:JSON.stringify({intent:{moduleID,actionID,targetID,value}})});
            const prepared=await preparedResponse.json(); if(!preparedResponse.ok) throw new Error(prepared.error||'Action is unavailable');
            if(!confirm(prepared.preview)) return;
            const executeResponse=await fetch('/api/hub/actions/execute',{method:'POST',headers:{...authHeaders(),'Content-Type':'application/json'},body:JSON.stringify({intent:prepared.intent,actionToken:prepared.actionToken})});
            const result=await executeResponse.json(); if(!executeResponse.ok) throw new Error(result.error||'Action failed');
            alert(result.message); await refreshHub();
          } catch(error) { alert(error.message); }
        }

        async function refreshHub() {
          const response=await fetch('/api/hub/snapshot',{method:'POST',headers:{...authHeaders(),'Content-Type':'application/json'},cache:'no-store',body:JSON.stringify({requestedMode:selectedMode})});
          if(response.status===401) throw new Error('unauthorized');
          const body=await response.json(); if(!response.ok) throw new Error(body.error||'Hub unavailable');
          renderHub(body);
        }

        async function setMode(mode) {
          selectedMode=mode; localStorage.setItem(modeKey,mode);
          modes.querySelectorAll('[data-mode]').forEach(button=>button.classList.toggle('active',button.dataset.mode===selectedMode));
          try { await refreshHub(); } catch(error) { setStatus('Mac offline'); }
        }

        async function refresh() {
          if(!deviceToken) { pair.classList.remove('hidden'); approvals.innerHTML=''; hub.innerHTML=''; modes.classList.add('hidden'); hubTitle.classList.add('hidden'); approvalTitle.classList.add('hidden'); empty.classList.add('hidden'); setStatus('Pairing required'); return; }
          try {
            const response=await fetch('/api/approvals',{headers:authHeaders(),cache:'no-store'});
            if(response.status===401) { deviceToken=''; localStorage.removeItem(tokenKey); pair.classList.remove('hidden'); setStatus('Pairing required'); return; }
            const body=await response.json(); if(!response.ok) throw new Error(body.error||'Mac unavailable');
            pair.classList.add('hidden'); render(body.approvals||[]); await refreshHub(); setStatus(`${body.approvals.length} pending`,true);
          } catch(error) { setStatus('Mac offline'); }
        }

        document.getElementById('pairButton').addEventListener('click',pairDevice);
        document.getElementById('code').addEventListener('keydown',event=>{if(event.key==='Enter')pairDevice();});
        modes.querySelectorAll('[data-mode]').forEach(button=>button.addEventListener('click',()=>setMode(button.dataset.mode)));
        if('serviceWorker' in navigator) navigator.serviceWorker.register('/sw.js').catch(()=>{});
        refresh(); setInterval(()=>{if(document.visibilityState==='visible')refresh();},4000);
        document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='visible')refresh();});
      </script>
    </body>
    </html>
    """#
}
