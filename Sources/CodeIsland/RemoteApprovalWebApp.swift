import Foundation

enum RemoteApprovalWebApp {
    static let manifest = #"""
    {
      "name": "CodeIsland Approvals",
      "short_name": "Approvals",
      "start_url": "/",
      "display": "standalone",
      "background_color": "#070a08",
      "theme_color": "#101611",
      "icons": []
    }
    """#

    static let serviceWorker = #"""
    const CACHE = 'codeisland-approvals-v1';
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
      <meta name="apple-mobile-web-app-title" content="Approvals">
      <link rel="manifest" href="/manifest.webmanifest">
      <title>CodeIsland Approvals</title>
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
        .hidden { display:none !important; }
        #error { color:#ff9da0; font-size:13px; margin-top:10px; white-space:pre-wrap; }
        footer { text-align:center; color:#657067; font-size:11px; padding:18px 0; }
      </style>
    </head>
    <body>
      <main>
        <header>
          <div class="mark" aria-hidden="true"></div>
          <div><h1>CodeIsland</h1><div class="subtitle">Private approval hub</div></div>
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

        <section id="approvals"></section>
        <section id="empty" class="card empty hidden">
          <strong>No approvals waiting</strong>
          <span class="muted">This page checks the Mac every four seconds.</span>
        </section>
        <footer>Tailnet-only · exact-request validation · single-use actions</footer>
      </main>
      <script>
        const tokenKey = 'codeisland.remote.deviceToken.v1';
        let deviceToken = localStorage.getItem(tokenKey) || '';
        let busy = new Set();
        const pair = document.getElementById('pair');
        const approvals = document.getElementById('approvals');
        const empty = document.getElementById('empty');
        const status = document.getElementById('status');
        const dot = document.getElementById('dot');
        const errorBox = document.getElementById('error');

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
        }

        async function refresh() {
          if(!deviceToken) { pair.classList.remove('hidden'); approvals.innerHTML=''; empty.classList.add('hidden'); setStatus('Pairing required'); return; }
          try {
            const response=await fetch('/api/approvals',{headers:authHeaders(),cache:'no-store'});
            if(response.status===401) { deviceToken=''; localStorage.removeItem(tokenKey); pair.classList.remove('hidden'); setStatus('Pairing required'); return; }
            const body=await response.json(); if(!response.ok) throw new Error(body.error||'Mac unavailable');
            pair.classList.add('hidden'); render(body.approvals||[]); setStatus(`${body.approvals.length} pending`,true);
          } catch(error) { setStatus('Mac offline'); }
        }

        document.getElementById('pairButton').addEventListener('click',pairDevice);
        document.getElementById('code').addEventListener('keydown',event=>{if(event.key==='Enter')pairDevice();});
        if('serviceWorker' in navigator) navigator.serviceWorker.register('/sw.js').catch(()=>{});
        refresh(); setInterval(()=>{if(document.visibilityState==='visible')refresh();},4000);
        document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='visible')refresh();});
      </script>
    </body>
    </html>
    """#
}

