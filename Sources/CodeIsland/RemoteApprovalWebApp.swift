import Foundation

enum RemoteApprovalWebApp {
    static let manifest = #"""
    {
      "name": "CodeIsland",
      "short_name": "CodeIsland",
      "start_url": "/",
      "display": "standalone",
      "background_color": "#070a08",
      "theme_color": "#101611",
      "icons": [
        {
          "src": "/app-icon.svg",
          "sizes": "any",
          "type": "image/svg+xml",
          "purpose": "any maskable"
        }
      ]
    }
    """#

    static let iconSVG = #"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" role="img" aria-label="CodeIsland">
      <rect width="1024" height="1024" rx="220" fill="#f7f4ec"/>
      <rect x="255" y="409" width="515" height="206" rx="103" fill="#1a1a1a"/>
      <rect x="358" y="461" width="103" height="103" rx="8" fill="#f5a623"/>
      <rect x="564" y="461" width="103" height="103" rx="8" fill="#f5a623"/>
      <rect x="410" y="461" width="51" height="51" rx="4" fill="#ffffff"/>
      <rect x="616" y="461" width="51" height="51" rx="4" fill="#ffffff"/>
    </svg>
    """#

    static let serviceWorker = #"""
    const CACHE = 'codeisland-personal-hub-v3';
    self.addEventListener('install', event => {
      event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(['/', '/manifest.webmanifest', '/app-icon.svg'])));
      self.skipWaiting();
    });
    self.addEventListener('activate', event => event.waitUntil(
      caches.keys()
        .then(keys => Promise.all(keys.filter(key => key !== CACHE).map(key => caches.delete(key))))
        .then(() => self.clients.claim())
    ));
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
      <link rel="icon" href="/app-icon.svg" type="image/svg+xml">
      <link rel="manifest" href="/manifest.webmanifest">
      <title>CodeIsland</title>
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
        button:focus-visible,.claude-file-label:focus-visible { outline:3px solid var(--amber); outline-offset:3px; }
        .deny { background:#351517; color:#ffbec0; box-shadow:inset 0 0 0 1px #6c2b30; }
        .approve { background:var(--green); color:#061008; }
        .secondary { background:#1a221c; color:#dce3dd; box-shadow:inset 0 0 0 1px #344037; }
        input { width:100%; min-height:50px; border:1px solid #344037; border-radius:12px; padding:0 13px; color:#f4f7f4; background:#080c09; font-size:16px; outline:none; }
        input:focus { border-color:var(--green); box-shadow:0 0 0 3px #4dd96b22; }
        label { display:block; color:#aeb8b0; font-size:12px; font-weight:650; margin:12px 0 6px; }
        .empty { text-align:center; padding:34px 18px; }
        .empty strong { display:block; font-size:17px; margin-bottom:6px; }
        .modes { display:grid; grid-template-columns:repeat(4,1fr); gap:6px; margin:0 0 12px; }
        .mode { min-height:44px; border-radius:10px; background:#141a16; color:#8d9b90; font:750 12px -apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif; }
        .mode.active { background:var(--amber); color:#171006; }
        .section-title { margin:18px 2px 8px; color:#9daa9f; font:750 11px ui-monospace,SFMono-Regular,Menlo,monospace; text-transform:uppercase; letter-spacing:.12em; }
        .module-grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(260px,1fr)); gap:10px; }
        .module { border:1px solid #29312b; background:#0e1310; border-radius:15px; padding:13px; }
        .module-head { display:flex; align-items:flex-start; gap:9px; }
        .module-title { font-size:15px; font-weight:750; }
        .module-summary { margin-top:3px; color:#8d9b90; font-size:12px; line-height:1.35; }
        .module-detail { margin-top:9px; padding:9px; border-radius:10px; background:#050806; color:#7f8b81; font:600 10px/1.45 ui-monospace,SFMono-Regular,Menlo,monospace; box-shadow:inset 0 0 0 1px #ffffff0d; }
        .module-detail strong { color:var(--amber); font-weight:800; }
        .availability { margin-left:auto; color:var(--amber); font:750 9px ui-monospace,SFMono-Regular,Menlo,monospace; text-transform:uppercase; }
        .hub-item { margin-top:8px; padding:9px; border-radius:10px; background:#050806; }
        .hub-item-title { font-size:12px; font-weight:700; overflow-wrap:anywhere; }
        .hub-item-subtitle { margin-top:2px; color:#78847a; font-size:10px; }
        .hub-item-detail { margin-top:8px; color:#c6cec8; font-size:12px; line-height:1.5; white-space:pre-wrap; overflow-wrap:anywhere; }
        .media-item-head { display:flex; align-items:center; gap:9px; }
        .media-art { width:52px; height:52px; flex:0 0 52px; border-radius:11px; object-fit:cover; box-shadow:0 8px 22px #0009,inset 0 0 0 1px #ffffff18; }
        .media-copy { min-width:0; flex:1; }
        .media-seek { width:100%; min-height:44px; height:44px; margin-top:5px; padding:0; border:0; background:transparent; box-shadow:none; accent-color:var(--amber); }
        .media-times { display:flex; justify-content:space-between; color:#78847a; font:650 9px ui-monospace,SFMono-Regular,Menlo,monospace; }
        .hub-actions { display:flex; flex-wrap:wrap; gap:6px; margin-top:8px; }
        .hub-action { min-height:44px; padding:0 12px; border-radius:9px; background:#1b241e; color:#dce3dd; font-size:12px; box-shadow:inset 0 0 0 1px #344037; }
        .hub-action.primary { background:var(--amber); color:#171006; box-shadow:none; }
        .hub-config { margin:0 0 10px; padding:13px; }
        .hub-config-head { display:flex; align-items:center; gap:10px; }
        .hub-config-actions { display:flex; flex-wrap:wrap; gap:7px; margin-top:10px; }
        .hub-config-actions button { min-height:44px; padding:0 12px; border-radius:9px; font-size:12px; }
        .rack-summary { margin-top:7px; color:#aeb8b0; font-size:11px; line-height:1.45; }
        .calendar-month { margin-top:10px; padding:10px; border-radius:13px; background:#070a08; box-shadow:inset 0 0 0 1px #ffffff12; }
        .calendar-head { display:flex; align-items:center; gap:8px; margin-bottom:8px; }
        .calendar-title { flex:1; text-align:center; font-size:13px; font-weight:760; letter-spacing:-.01em; }
        .calendar-nav { min-width:44px; min-height:44px; padding:0 10px; border-radius:999px; background:#1b241e; color:var(--amber); font-size:12px; box-shadow:inset 0 0 0 1px #344037; }
        .calendar-grid { display:grid; grid-template-columns:repeat(7,minmax(0,1fr)); gap:4px; }
        .calendar-weekday { color:#667268; text-align:center; font:800 9px ui-monospace,SFMono-Regular,Menlo,monospace; }
        .calendar-day { position:relative; min-height:44px; padding:3px; border-radius:9px; background:transparent; color:#dce3dd; font-size:12px; box-shadow:none; }
        .calendar-day.adjacent { color:#59635b; }
        .calendar-day.selected { background:#ffb3472e; box-shadow:inset 0 0 0 1px #ffb34766; }
        .calendar-day.today { box-shadow:inset 0 0 0 1px var(--amber); }
        .calendar-count { display:block; width:4px; height:4px; margin:2px auto 0; border-radius:50%; background:var(--amber); box-shadow:0 0 7px #ffb34799; }
        .calendar-selected { margin-top:8px; }
        progress { width:100%; height:5px; margin-top:7px; accent-color:var(--amber); }
        .media-preflight { position:fixed; inset:0; z-index:100; display:grid; place-items:center; background:#010201; color:#f4f7f4; }
        .media-preflight video { width:100%; height:100%; object-fit:cover; transform:scaleX(-1); }
        .media-preflight-scrim { position:absolute; inset:0; pointer-events:none; background:linear-gradient(180deg,#000b 0,#0000 28%,#0000 58%,#000d 100%); }
        .media-preflight-top { position:absolute; top:max(18px,env(safe-area-inset-top)); left:18px; right:18px; display:flex; align-items:flex-start; justify-content:space-between; gap:16px; }
        .media-preflight-copy { max-width:440px; text-shadow:0 2px 18px #000; }
        .media-preflight-copy strong { display:block; font-size:20px; letter-spacing:-.02em; }
        .media-preflight-copy span { display:block; margin-top:5px; color:#d2dad4; font-size:12px; line-height:1.4; }
        .media-preflight-close { min-width:72px; min-height:44px; border-radius:999px; background:#f4f7f4; color:#071008; box-shadow:0 8px 28px #0008; }
        .media-preflight-bottom { position:absolute; left:18px; right:18px; bottom:max(22px,env(safe-area-inset-bottom)); padding:14px; border:1px solid #ffffff24; border-radius:17px; background:#071008dd; backdrop-filter:blur(18px); box-shadow:0 18px 60px #0008; }
        .media-preflight-private { color:var(--green); font:800 10px ui-monospace,SFMono-Regular,Menlo,monospace; letter-spacing:.11em; text-transform:uppercase; }
        .media-preflight-status { margin-top:5px; color:#aeb8b0; font-size:12px; }
        .media-preflight-meter { height:7px; margin-top:11px; overflow:hidden; border-radius:999px; background:#ffffff14; }
        .media-preflight-level { width:0; height:100%; border-radius:inherit; background:linear-gradient(90deg,var(--green),var(--amber)); transition:width 90ms linear; }
        .claude-composer { position:fixed; inset:0; z-index:110; display:grid; place-items:center; padding:18px; background:#010201e8; }
        .claude-composer-card { width:min(560px,100%); max-height:calc(100vh - 36px); overflow:auto; padding:18px; border:1px solid #ffffff1f; border-radius:20px; background:linear-gradient(145deg,#141a16,#090d0a); box-shadow:0 28px 90px #000c; }
        .claude-composer-card textarea { width:100%; min-height:150px; resize:vertical; margin:12px 0 8px; border:1px solid #344037; border-radius:13px; padding:12px; color:#f4f7f4; background:#050806; font:15px/1.45 -apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif; outline:none; }
        .claude-composer-card textarea:focus { border-color:var(--amber); box-shadow:0 0 0 3px #ffb34722; }
        .claude-composer-controls { display:flex; flex-wrap:wrap; gap:7px; margin:8px 0; }
        .claude-composer-controls button,.claude-file-label { min-height:44px; display:inline-flex; align-items:center; padding:0 12px; border-radius:10px; background:#1b241e; color:#dce3dd; font-size:12px; font-weight:750; box-shadow:inset 0 0 0 1px #344037; cursor:pointer; }
        .claude-contexts { color:#aeb8b0; font:650 10px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace; }
        .claude-disclosure { margin-top:10px; color:#718075; font-size:11px; line-height:1.4; }
        .hidden { display:none !important; }
        #error { color:#ff9da0; font-size:13px; margin-top:10px; white-space:pre-wrap; }
        .notice { position:sticky; top:max(8px,env(safe-area-inset-top)); z-index:20; margin:0 0 12px; padding:12px 14px; border:1px solid #4a5a4d; border-radius:13px; background:#151d17f2; color:#e8eee9; box-shadow:0 14px 44px #0008; font-size:13px; line-height:1.4; }
        .notice.error { border-color:#77363a; color:#ffc4c6; }
        footer { text-align:center; color:#657067; font-size:11px; padding:18px 0; }
      </style>
    </head>
    <body>
      <main>
        <header>
          <div class="mark" aria-hidden="true"></div>
          <div><h1>CodeIsland</h1><div class="subtitle">Your Mac, when it needs you</div></div>
          <div class="status"><span id="dot" class="dot"></span><span id="status">Connecting</span></div>
        </header>
        <div id="notice" class="notice hidden" role="status" aria-live="polite"></div>

        <section id="pair" class="card hidden">
          <div class="eyebrow">Pair this iPhone</div>
          <div class="tool">Connect to Greg's Mac</div>
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

        <div id="questionTitle" class="section-title hidden">Now · agent questions</div>
        <section id="questions"></section>
        <div id="approvalTitle" class="section-title hidden">Now · agent approvals</div>
        <section id="approvals"></section>
        <section id="empty" class="card empty hidden">
          <strong>You're clear for now</strong>
          <span class="muted">CodeIsland checks your Mac every four seconds.</span>
        </section>

        <nav id="modes" class="modes hidden" aria-label="Context">
          <button class="mode" data-mode="auto">Auto</button>
          <button class="mode" data-mode="home">Home</button>
          <button class="mode" data-mode="work">Work</button>
          <button class="mode" data-mode="code">Code</button>
        </nav>
        <div id="hubTitle" class="section-title hidden">Today &amp; tools</div>
        <section id="hubConfig" class="module hub-config hidden"></section>
        <section id="hub" class="module-grid"></section>
        <footer>Tailnet-only · exact-request validation · single-use actions</footer>
      </main>
      <section id="claudeComposer" class="claude-composer hidden" role="dialog" aria-modal="true" aria-labelledby="claudeComposerTitle">
        <div class="claude-composer-card">
          <div class="eyebrow">Private Mac copilot</div>
          <div id="claudeComposerTitle" class="tool">Ask Claude</div>
          <textarea id="claudePrompt" placeholder="Ask a question or describe the actions Claude should propose"></textarea>
          <div class="claude-composer-controls">
            <button id="claudeHold" type="button">Hold to talk</button>
            <button id="claudeContinuous" type="button">Continuous</button>
            <label class="claude-file-label" for="claudeFiles">Attach text</label>
            <input id="claudeFiles" class="hidden" type="file" multiple accept=".txt,.md,.swift,.json,.yml,.yaml,.log,.csv,.ts,.tsx,.js,.jsx,.py,.sh,.zsh,.rb,.html,.css,.sql,.toml,.xml,text/*">
          </div>
          <div id="claudeContexts" class="claude-contexts">No files attached · 5 max · 2 MB each</div>
          <div id="claudeSpeechStatus" class="claude-contexts">Voice stays off until you press a voice control.</div>
          <div class="claude-disclosure">Voice and bounded text are sent only to your paired Mac. Ask has no tools. Do returns proposals that require another exact confirmation.</div>
          <div class="actions">
            <button id="claudeCancel" class="deny">Cancel</button>
            <button id="claudeReview" class="approve">Review</button>
          </div>
        </div>
      </section>
      <section id="mediaPreflight" class="media-preflight hidden" role="dialog" aria-modal="true" aria-labelledby="mediaPreflightTitle">
        <video id="mediaPreflightVideo" autoplay muted playsinline></video>
        <div class="media-preflight-scrim" aria-hidden="true"></div>
        <div class="media-preflight-top">
          <div class="media-preflight-copy"><strong id="mediaPreflightTitle">Camera & microphone check</strong><span>Preview what your camera sees and confirm microphone input before a call or recording.</span></div>
          <button id="mediaPreflightDone" class="media-preflight-close">Done</button>
        </div>
        <div class="media-preflight-bottom">
          <div class="media-preflight-private">Local only</div>
          <div id="mediaPreflightStatus" class="media-preflight-status">Requesting camera and microphone access…</div>
          <div class="media-preflight-meter" aria-label="Microphone input level"><div id="mediaPreflightLevel" class="media-preflight-level"></div></div>
        </div>
      </section>
      <script>
        const tokenKey = 'codeisland.remote.deviceToken.v1';
        const modeKey = 'codeisland.hub.mode.v1';
        let deviceToken = localStorage.getItem(tokenKey) || '';
        let selectedMode = localStorage.getItem(modeKey) || 'auto';
        var calendarReferenceDate = null;
        var calendarSelectedDate = null;
        let busy = new Set();
        let lastHubSnapshot = { value: null };
        const mediaSeekState = { active: false };
        const localMedia = { stream:null, audioContext:null, source:null, analyser:null, frame:0, lastMeterAt:0, priorFocus:null };
        const claudeInput = { resolve:null, contexts:[], recognition:null, silenceTimer:0, baseText:'', priorFocus:null };
        const pair = document.getElementById('pair');
        const approvals = document.getElementById('approvals');
        const questions = document.getElementById('questions');
        const empty = document.getElementById('empty');
        const status = document.getElementById('status');
        const dot = document.getElementById('dot');
        const errorBox = document.getElementById('error');
        const modes = document.getElementById('modes');
        const hub = document.getElementById('hub');
        const hubConfig = document.getElementById('hubConfig');
        const hubTitle = document.getElementById('hubTitle');
        const approvalTitle = document.getElementById('approvalTitle');
        const questionTitle = document.getElementById('questionTitle');
        const notice = document.getElementById('notice');
        const mediaPreflight = document.getElementById('mediaPreflight');
        const mediaPreflightVideo = document.getElementById('mediaPreflightVideo');
        const mediaPreflightStatus = document.getElementById('mediaPreflightStatus');
        const mediaPreflightLevel = document.getElementById('mediaPreflightLevel');
        const mediaPreflightDone = document.getElementById('mediaPreflightDone');
        const claudeComposer = document.getElementById('claudeComposer');
        const claudeComposerTitle = document.getElementById('claudeComposerTitle');
        const claudePrompt = document.getElementById('claudePrompt');
        const claudeFiles = document.getElementById('claudeFiles');
        const claudeContexts = document.getElementById('claudeContexts');
        const claudeSpeechStatus = document.getElementById('claudeSpeechStatus');
        const claudeHold = document.getElementById('claudeHold');
        const claudeContinuous = document.getElementById('claudeContinuous');

        const moduleNames = {
          nowPlaying:'Now Playing',shelf:'Shelf',calendar:'Calendar',reminders:'Tasks',notes:'Notes',
          system:'System',weather:'Weather',notifications:'Notifications',claude:'Claude',agents:'Agents',
          github:'GitHub',audio:'Audio',bluetooth:'Bluetooth',battery:'Battery',quickToggles:'Quick Toggles',
          downloads:'Downloads',camera:'Camera',teleprompter:'Prompter',windowManager:'Windows'
        };

        function authHeaders() { return { 'Authorization': `Bearer ${deviceToken}` }; }
        function setStatus(text, live=false) { status.textContent=text; dot.classList.toggle('live',live); }
        let noticeTimer={ value:0 };
        function notify(message,error=false) {
          clearTimeout(noticeTimer.value); notice.textContent=String(message||''); notice.classList.toggle('error',error); notice.classList.remove('hidden');
          noticeTimer.value=setTimeout(()=>notice.classList.add('hidden'),5000);
        }
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
          } catch(error) { notify(error.message,true); await refresh(); }
          finally { busy.delete(id); }
        }

        let lastItems=[];
        let lastQuestions=[];
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
          updateWaitingState();
          approvalTitle.classList.toggle('hidden',lastItems.length===0);
        }

        function renderQuestions(items) {
          lastQuestions=items;
          questions.innerHTML=items.map(item=>`<article class="card approval" data-question-id="${escapeHTML(item.id)}">
            <div class="eyebrow">${escapeHTML(item.source)} · QUESTION · ${relativeTime(item.createdAt)}</div>
            ${item.requiresLocalResponse
              ? `<div class="tool">Sensitive question waiting on Mac</div><div class="muted">Its text and choices are intentionally never sent to this device.</div>`
              : (item.prompts||[]).map((prompt,promptIndex)=>`<div class="question-prompt" data-prompt-index="${promptIndex}">
                  ${prompt.header?`<div class="eyebrow">${escapeHTML(prompt.header)}</div>`:''}
                  <div class="tool">${escapeHTML(prompt.question)}</div>
                  ${(prompt.options||[]).map(option=>`<label class="hub-item"><input class="question-option" type="${prompt.allowsMultipleSelection?'checkbox':'radio'}" name="question-${escapeHTML(item.id)}-${promptIndex}" value="${escapeHTML(option)}"> ${escapeHTML(option)}</label>`).join('')}
                  <input class="question-custom" placeholder="${prompt.options&&prompt.options.length?'Or type a custom answer':'Type your answer'}">
                </div>`).join('') + `<div class="actions" style="grid-template-columns:1fr"><button class="approve question-send" data-id="${escapeHTML(item.id)}" data-token="${escapeHTML(item.actionToken||'')}">Send answer</button></div>`}
          </article>`).join('');
          questions.querySelectorAll('button.question-send').forEach(button=>button.addEventListener('click',()=>answerQuestion(button)));
          questionTitle.classList.toggle('hidden',items.length===0);
          updateWaitingState();
        }

        function updateWaitingState() {
          empty.classList.toggle('hidden',lastItems.length!==0||lastQuestions.length!==0);
        }

        async function answerQuestion(button) {
          const id=button.dataset.id; if(busy.has(id)) return;
          const card=button.closest('[data-question-id]');
          const answers=Array.from(card.querySelectorAll('.question-prompt')).map(prompt=>{
            const selected=Array.from(prompt.querySelectorAll('.question-option:checked')).map(input=>input.value);
            const custom=prompt.querySelector('.question-custom').value.trim(); if(custom) selected.push(custom);
            return selected.join(', ');
          });
          if(answers.some(answer=>!answer)) { notify('Answer every prompt first.',true); return; }
          if(!confirm('Send this answer to the exact waiting agent request?')) return;
          busy.add(id); button.disabled=true;
          try {
            const response=await fetch(`/api/questions/${encodeURIComponent(id)}/answer`,{method:'POST',headers:{...authHeaders(),'Content-Type':'application/json'},body:JSON.stringify({answers,actionToken:button.dataset.token})});
            const body=await response.json(); if(!response.ok) throw new Error(body.error||'Answer failed');
            await refresh();
          } catch(error) { notify(error.message,true); await refresh(); }
          finally { busy.delete(id); }
        }

        function renderHub(snapshot) {
          lastHubSnapshot.value=snapshot;
          hubTitle.textContent=`${snapshot.resolvedMode.toUpperCase()} · ${snapshot.serverName}`;
          hubTitle.classList.remove('hidden'); modes.classList.remove('hidden');
          modes.querySelectorAll('[data-mode]').forEach(button=>button.classList.toggle('active',button.dataset.mode===selectedMode));
          renderHubConfiguration(snapshot);
          hub.innerHTML=(snapshot.modules||[]).map(module=>`<article class="module">
            <div class="module-head"><div><div class="module-title">${escapeHTML(moduleNames[module.id]||module.id)}</div><div class="module-summary">${escapeHTML(module.summary||'')}</div></div><div class="availability">${escapeHTML(module.availability)}</div></div>
            ${module.detail?`<div class="module-detail">${module.id==='notifications'?'<strong>SYSTEM LIMIT</strong> · ':''}${escapeHTML(module.detail)}</div>`:''}
            ${renderCalendarMonth(module)}
            ${(module.calendarMonth?(module.items||[]).slice(0,6):(module.items||[])).map(item=>renderHubItem(module.id,item)).join('')}
            ${renderHubActions(module.id,module.actions||[],null,'')}
          </article>`).join('');
          hub.querySelectorAll('[data-hub-action]').forEach(button=>button.addEventListener('click',()=>runHubAction(button.dataset.module,button.dataset.action,button.dataset.target||null,button.dataset.deeplink||null,button.dataset.payload||'',button.dataset.value||'')));
          hub.querySelectorAll('[data-calendar-nav]').forEach(button=>button.addEventListener('click',()=>navigateCalendar(button.dataset.calendarNav)));
          hub.querySelectorAll('[data-calendar-date]').forEach(button=>button.addEventListener('click',()=>selectCalendarDate(button.dataset.calendarDate)));
          hub.querySelectorAll('[data-media-seek]').forEach(slider=>{
            const label=slider.parentElement.querySelector('[data-media-current]');
            slider.addEventListener('pointerdown',()=>{mediaSeekState.active=true;});
            slider.addEventListener('focus',()=>{mediaSeekState.active=true;});
            slider.addEventListener('input',()=>{if(label) label.textContent=playbackTime(Number(slider.value));});
            slider.addEventListener('change',async()=>{
              mediaSeekState.active=false;
              await runHubAction('nowPlaying','seek',slider.dataset.target||'current',null,'',slider.value);
            });
            slider.addEventListener('blur',()=>{mediaSeekState.active=false;});
          });
        }

        function renderHubItem(moduleID,item) {
          const artwork=typeof item.artworkDataURL==='string'&&/^data:image\/jpeg;base64,[A-Za-z0-9+/=]+$/.test(item.artworkDataURL)?item.artworkDataURL:'';
          const position=Number(item.mediaPosition); const duration=Number(item.mediaDuration);
          const visibleDetail=moduleID==='claude'&&item.detail?`<div class="hub-item-detail">${escapeHTML(item.detail)}</div>`:'';
          const seek=Number.isFinite(position)&&Number.isFinite(duration)&&duration>0
            ? `<input class="media-seek" type="range" min="0" max="${duration}" step="0.1" value="${Math.min(Math.max(position,0),duration)}" data-media-seek="1" data-target="${escapeHTML(item.id)}" aria-label="Playback position"><div class="media-times"><span data-media-current>${playbackTime(position)}</span><span>${playbackTime(duration)}</span></div>`:'';
          return `<div class="hub-item"><div class="media-item-head">${artwork?`<img class="media-art" src="${escapeHTML(artwork)}" alt="">`:''}<div class="media-copy"><div class="hub-item-title">${escapeHTML(item.title)}</div>${item.subtitle?`<div class="hub-item-subtitle">${escapeHTML(item.subtitle)}</div>`:''}</div></div>${visibleDetail}${item.progress!==null&&item.progress!==undefined?`<progress value="${Number(item.progress)}" max="1"></progress>`:''}${seek}${renderHubActions(moduleID,item.actions||[],item.id,item.detail||'')}</div>`;
        }

        function playbackTime(seconds) {
          const whole=Math.max(0,Math.round(Number.isFinite(seconds)?seconds:0));
          return `${Math.floor(whole/60)}:${String(whole%60).padStart(2,'0')}`;
        }

        function releaseLocalMedia() {
          if(localMedia.frame) cancelAnimationFrame(localMedia.frame);
          localMedia.frame=0; localMedia.lastMeterAt=0;
          if(localMedia.source) { try { localMedia.source.disconnect(); } catch(error) {} }
          localMedia.source=null; localMedia.analyser=null;
          if(localMedia.audioContext) localMedia.audioContext.close().catch(()=>{});
          localMedia.audioContext=null;
          if(localMedia.stream) localMedia.stream.getTracks().forEach(track=>track.stop());
          localMedia.stream=null; mediaPreflightVideo.srcObject=null; mediaPreflightLevel.style.width='0%';
        }

        function closeMediaPreflight() {
          releaseLocalMedia(); mediaPreflight.classList.add('hidden'); document.querySelector('main').inert=false;
          if(localMedia.priorFocus&&typeof localMedia.priorFocus.focus==='function') localMedia.priorFocus.focus();
          localMedia.priorFocus=null;
        }

        function updateMediaMeter(timestamp) {
          if(!localMedia.analyser||!localMedia.stream) return;
          if(timestamp-localMedia.lastMeterAt>=80) {
            const samples=new Float32Array(localMedia.analyser.fftSize); localMedia.analyser.getFloatTimeDomainData(samples);
            let squares=0; let peak=0;
            for(const sample of samples) { squares+=sample*sample; peak=Math.max(peak,Math.abs(sample)); }
            const rms=Math.sqrt(squares/samples.length); const level=Math.min(100,Math.round(Math.max(rms*420,peak*100)));
            mediaPreflightLevel.style.width=`${level}%`; localMedia.lastMeterAt=timestamp;
          }
          localMedia.frame=requestAnimationFrame(updateMediaMeter);
        }

        async function openMediaPreflight() {
          releaseLocalMedia(); localMedia.priorFocus=document.activeElement;
          mediaPreflightStatus.textContent='Requesting camera and microphone access…';
          mediaPreflight.classList.remove('hidden'); document.querySelector('main').inert=true; mediaPreflightDone.focus();
          try {
            if(!navigator.mediaDevices?.getUserMedia) throw new Error('This browser does not provide camera and microphone access.');
            const stream=await navigator.mediaDevices.getUserMedia({video:{facingMode:'user'},audio:{echoCancellation:false,noiseSuppression:false,autoGainControl:false}});
            if(mediaPreflight.classList.contains('hidden')) { stream.getTracks().forEach(track=>track.stop()); return; }
            localMedia.stream=stream; mediaPreflightVideo.srcObject=stream; await mediaPreflightVideo.play().catch(()=>{});
            const AudioContextClass=window.AudioContext||window.webkitAudioContext;
            if(AudioContextClass&&stream.getAudioTracks().length) {
              localMedia.audioContext=new AudioContextClass(); localMedia.source=localMedia.audioContext.createMediaStreamSource(stream);
              localMedia.analyser=localMedia.audioContext.createAnalyser(); localMedia.analyser.fftSize=512; localMedia.source.connect(localMedia.analyser);
              localMedia.frame=requestAnimationFrame(updateMediaMeter);
            }
            mediaPreflightStatus.textContent='Camera and microphone are available. Nothing leaves this browser.';
          } catch(error) {
            releaseLocalMedia(); mediaPreflightStatus.textContent=error?.message||'Camera or microphone access was denied.';
          }
        }

        function renderCalendarMonth(module) {
          const month=module.calendarMonth; if(!month) return '';
          const title=new Intl.DateTimeFormat(undefined,{month:'long',year:'numeric'}).format(new Date(month.displayedMonth));
          const selectedDay=new Date(month.selectedDate).toDateString();
          const weekdays=['S','M','T','W','T','F','S'];
          const days=(month.days||[]).map(day=>{
            const date=new Date(day.date); const selected=date.toDateString()===selectedDay;
            const classes=['calendar-day',day.isInDisplayedMonth?'':'adjacent',selected?'selected':'',day.isToday?'today':''].filter(Boolean).join(' ');
            return `<button class="${classes}" data-calendar-date="${escapeHTML(day.date)}" aria-label="${escapeHTML(date.toLocaleDateString(undefined,{dateStyle:'full'}))}, ${Number(day.eventCount)||0} events">${date.getDate()}${day.eventCount?'<span class="calendar-count"></span>':''}</button>`;
          }).join('');
          const selectedEvents=(month.selectedEvents||[]).map(item=>renderHubItem(module.id,item)).join('');
          return `<div class="calendar-month"><div class="calendar-head"><button class="calendar-nav" data-calendar-nav="previous" aria-label="Previous month">‹</button><button class="calendar-nav" data-calendar-nav="today">Today</button><div class="calendar-title">${escapeHTML(title)}</div><button class="calendar-nav" data-calendar-nav="next" aria-label="Next month">›</button></div><div class="calendar-grid">${weekdays.map(day=>`<div class="calendar-weekday">${day}</div>`).join('')}${days}</div><div class="calendar-selected">${selectedEvents||'<div class="hub-item-subtitle">No events on the selected day</div>'}</div></div>`;
        }

        async function navigateCalendar(direction) {
          if(direction==='today') {
            const now=new Date(); calendarReferenceDate=now.toISOString(); calendarSelectedDate=now.toISOString();
          } else {
            const calendarModule=(lastHubSnapshot.value?.modules||[]).find(module=>module.id==='calendar');
            const displayed=new Date(calendarModule?.calendarMonth?.displayedMonth||Date.now());
            const next=new Date(displayed.getFullYear(),displayed.getMonth()+(direction==='next'?1:-1),1,12);
            calendarReferenceDate=next.toISOString(); calendarSelectedDate=next.toISOString();
          }
          await refreshHub();
        }

        async function selectCalendarDate(value) {
          const calendarModule=(lastHubSnapshot.value?.modules||[]).find(module=>module.id==='calendar');
          calendarReferenceDate=calendarModule?.calendarMonth?.displayedMonth||value;
          calendarSelectedDate=value;
          await refreshHub();
        }

        function renderHubConfiguration(snapshot) {
          const configuration=snapshot.configuration;
          if(!configuration) { hubConfig.classList.add('hidden'); hubConfig.innerHTML=''; return; }
          const rack=(configuration.racks||[]).find(item=>item.mode===snapshot.resolvedMode);
          const modules=rack?.modules||[];
          const dayProgress=Number(snapshot.dayProgress);
          const showDay=configuration.dashboardEnabled&&Number.isFinite(dayProgress);
          hubConfig.classList.remove('hidden');
          hubConfig.innerHTML=`<div class="hub-config-head"><div><div class="module-title">${escapeHTML(snapshot.resolvedMode.toUpperCase())} rack</div><div class="module-summary">Saved across Mac, iPhone, and web</div></div><div class="availability">${configuration.dashboardEnabled?'DASHBOARD ON':'DASHBOARD OFF'}</div></div>
            ${showDay?`<div class="rack-summary">Day progress · ${Math.round(dayProgress*100)}%</div><progress value="${dayProgress}" max="1"></progress>`:''}
            <div class="rack-summary">${modules.map(id=>escapeHTML(moduleNames[id]||id)).join(' · ')}</div>
            <div class="hub-config-actions"><button id="editRack" class="hub-action primary">Edit rack</button><button id="toggleDashboard" class="hub-action">${configuration.dashboardEnabled?'Hide dashboard':'Show dashboard'}</button></div>`;
          document.getElementById('editRack').addEventListener('click',()=>editRack(snapshot,modules));
          document.getElementById('toggleDashboard').addEventListener('click',()=>runHubAction('quickToggles','setDashboard',null,null,'',JSON.stringify({dashboardEnabled:!configuration.dashboardEnabled})));
        }

        async function editRack(snapshot,currentModules) {
          const catalog=Object.keys(moduleNames);
          const answer=prompt(`Enter ${snapshot.resolvedMode.toUpperCase()} modules in order, separated by commas.\n\nAvailable: ${catalog.join(', ')}`,currentModules.join(', '));
          if(answer===null) return;
          const reverseNames=Object.fromEntries(Object.entries(moduleNames).map(([id,title])=>[title.toLowerCase(),id]));
          const modules=answer.split(',').map(value=>value.trim()).filter(Boolean).map(value=>catalog.includes(value)?value:reverseNames[value.toLowerCase()]).filter(Boolean);
          if(!modules.length) { notify('Keep at least one valid module in the rack.',true); return; }
          if(new Set(modules).size!==modules.length) { notify('A module can appear only once.',true); return; }
          await runHubAction('quickToggles','setModeRack',null,null,'',JSON.stringify({mode:snapshot.resolvedMode,modules}));
        }

        function renderHubActions(moduleID,actions,targetID,payload) {
          if(!actions.length) return '';
          return `<div class="hub-actions">${actions.map(action=>`<button class="hub-action ${action.role==='primary'?'primary':''}" data-hub-action="1" data-module="${escapeHTML(moduleID)}" data-action="${escapeHTML(action.id)}" data-target="${escapeHTML(action.targetID||targetID||'')}" data-deeplink="${escapeHTML(action.deepLink||'')}" data-payload="${escapeHTML(payload)}" data-value="${escapeHTML(action.value||'')}">${escapeHTML(action.label)}</button>`).join('')}</div>`;
        }

        function stopClaudeSpeech(message='Voice stopped.') {
          if(claudeInput.silenceTimer) clearTimeout(claudeInput.silenceTimer);
          claudeInput.silenceTimer=0;
          const recognition=claudeInput.recognition; claudeInput.recognition=null;
          if(recognition) { try { recognition.stop(); } catch(error) {} }
          claudeHold.textContent='Hold to talk'; claudeContinuous.textContent='Continuous';
          claudeSpeechStatus.textContent=message;
        }

        function scheduleClaudeSilenceStop() {
          if(claudeInput.silenceTimer) clearTimeout(claudeInput.silenceTimer);
          claudeInput.silenceTimer=setTimeout(()=>stopClaudeSpeech('Stopped after 3 seconds of silence.'),3000);
        }

        function startClaudeSpeech(continuous) {
          stopClaudeSpeech('Starting private voice input…');
          const Recognition=window.SpeechRecognition||window.webkitSpeechRecognition;
          if(!Recognition) { claudeSpeechStatus.textContent='Voice input is unavailable in this browser. Type your request instead.'; return; }
          const recognition=new Recognition(); claudeInput.recognition=recognition; claudeInput.baseText=claudePrompt.value.trim();
          recognition.continuous=continuous; recognition.interimResults=true; recognition.lang=document.documentElement.lang||'en-US';
          recognition.onstart=()=>{
            claudeSpeechStatus.textContent=continuous?'Listening continuously · stops after silence':'Listening while held';
            if(continuous) { claudeContinuous.textContent='Stop listening'; scheduleClaudeSilenceStop(); }
            else claudeHold.textContent='Listening…';
          };
          recognition.onresult=event=>{
            let spoken='';
            for(let index=0;index<event.results.length;index++) spoken+=event.results[index][0].transcript;
            claudePrompt.value=[claudeInput.baseText,spoken.trim()].filter(Boolean).join(' ');
            if(continuous) scheduleClaudeSilenceStop();
          };
          recognition.onerror=event=>stopClaudeSpeech(`Voice input unavailable: ${event.error||'permission denied'}`);
          recognition.onend=()=>{
            if(claudeInput.recognition===recognition) {
              claudeInput.recognition=null; claudeHold.textContent='Hold to talk'; claudeContinuous.textContent='Continuous';
              claudeSpeechStatus.textContent='Voice stopped. Review the transcript before continuing.';
            }
          };
          try { recognition.start(); } catch(error) { stopClaudeSpeech('Voice input could not start.'); }
        }

        async function loadClaudeFiles(files) {
          const allowed=new Set(['txt','md','swift','json','yml','yaml','log','csv','ts','tsx','js','jsx','py','sh','zsh','rb','html','css','sql','toml','xml']);
          if(files.length>5) throw new Error('Attach no more than 5 text files.');
          let remaining=20000; const contexts=[];
          for(const file of files) {
            const extension=(file.name.split('.').pop()||'').toLowerCase();
            if(!allowed.has(extension)) throw new Error(`${file.name} is not a supported text file.`);
            if(file.size>2000000) throw new Error(`${file.name} is larger than 2 MB.`);
            let text;
            try { text=new TextDecoder('utf-8',{fatal:true}).decode(await file.arrayBuffer()); }
            catch(error) { throw new Error(`${file.name} is not readable UTF-8 text.`); }
            const limit=Math.min(12000,remaining); const clipped=text.slice(0,limit); remaining=Math.max(0,remaining-clipped.length);
            contexts.push({name:file.name.slice(0,240),text:clipped,byteCount:file.size,wasTruncated:clipped.length<text.length});
          }
          return contexts;
        }

        function updateClaudeContextSummary() {
          if(!claudeInput.contexts.length) { claudeContexts.textContent='No files attached · 5 max · 2 MB each'; return; }
          claudeContexts.textContent=claudeInput.contexts.map(context=>`${context.name}${context.wasTruncated?' (truncated)':''}`).join(' · ');
        }

        function closeClaudeComposer(result=null) {
          stopClaudeSpeech(); claudeComposer.classList.add('hidden'); document.querySelector('main').inert=false;
          if(claudeInput.priorFocus&&typeof claudeInput.priorFocus.focus==='function') claudeInput.priorFocus.focus();
          claudeInput.priorFocus=null;
          const resolve=claudeInput.resolve; claudeInput.resolve=null; if(resolve) resolve(result);
        }

        function collectClaudeDraft(actionID) {
          if(claudeInput.resolve) closeClaudeComposer(null);
          claudeInput.contexts=[]; claudeFiles.value=''; claudePrompt.value=''; updateClaudeContextSummary();
          claudeComposerTitle.textContent=actionID==='plan'?'Propose actions with Claude':'Ask Claude';
          claudeSpeechStatus.textContent='Voice stays off until you press a voice control.';
          claudeInput.priorFocus=document.activeElement; claudeComposer.classList.remove('hidden'); document.querySelector('main').inert=true;
          setTimeout(()=>claudePrompt.focus(),0);
          return new Promise(resolve=>{claudeInput.resolve=resolve;});
        }

        async function runHubAction(moduleID,actionID,targetID,deepLink,payload,actionValue) {
          if(actionID==='downloadToDevice'&&targetID) {
            try {
              const fileModule=moduleID==='downloads'?'downloads':'shelf';
              const response=await fetch(`/api/hub/${fileModule}/${encodeURIComponent(targetID)}/file`,{headers:authHeaders()});
              if(!response.ok) { const body=await response.json(); throw new Error(body.error||'File transfer failed'); }
              const blob=await response.blob(); const url=URL.createObjectURL(blob); const link=document.createElement('a');
              const disposition=response.headers.get('Content-Disposition')||''; const match=disposition.match(/filename\*=UTF-8''([^;]+)/i);
              link.href=url; link.download=match?decodeURIComponent(match[1]):'CodeIsland-file'; document.body.appendChild(link); link.click(); link.remove(); setTimeout(()=>URL.revokeObjectURL(url),1000);
            } catch(error) { notify(error.message,true); }
            return;
          }
          if(moduleID==='camera'&&(actionID==='previewLocal'||actionID==='previewOnDevice')) {
            await openMediaPreflight();
            return;
          }
          if(actionID==='presentOnDevice') {
            const popup=window.open('','_blank'); if(!popup) { notify('Allow pop-ups to open the teleprompter',true); return; }
            popup.document.title='CodeIsland Teleprompter';
            const style=popup.document.createElement('style'); style.textContent='body{margin:0;background:#050505;color:#f5f5f5;font:600 42px/1.55 system-ui;padding:15vh 9vw 30vh}button{position:fixed;top:18px;right:18px;padding:10px 16px;background:#ffb000;color:#000;border:0;border-radius:10px;font-weight:800}'; popup.document.head.appendChild(style);
            const close=popup.document.createElement('button'); close.textContent='Done'; close.onclick=()=>popup.close(); popup.document.body.appendChild(close);
            const script=popup.document.createElement('div'); script.textContent=payload; popup.document.body.appendChild(script); return;
          }
          if(actionID==='copyToDevice') {
            try { await navigator.clipboard.writeText(payload); notify('Copied to this device'); }
            catch(error) { notify('Clipboard permission was denied',true); }
            return;
          }
          if(deepLink) { window.location.href=deepLink; return; }
          let value=actionValue||null;
          if((moduleID==='reminders'||moduleID==='notes')&&actionID==='add') {
            value=prompt(moduleID==='notes'?'New note':'New task'); if(!value||!value.trim()) return; value=value.trim();
            if(moduleID==='reminders') {
              const reminderModule=(lastHubSnapshot.value?.modules||[]).find(module=>module.id==='reminders');
              const lists=(reminderModule?.items||[]).filter(item=>String(item.id).startsWith('list:'));
              let calendarID=null;
              if(lists.length) {
                const choices=lists.map((item,index)=>`${index+1}. ${item.title}`).join('\n');
                const answer=prompt(`Choose list number:\n${choices}`,'1'); if(answer===null) return;
                const index=Number(answer)-1; if(!Number.isInteger(index)||index<0||index>=lists.length) { notify('Choose a valid list',true); return; }
                calendarID=lists[index].detail||null;
              }
              const dueText=(prompt('Due time (optional: YYYY-MM-DD HH:MM)','')||'').trim();
              let due=null;
              if(dueText) { const parsed=new Date(dueText.replace(' ','T')); if(Number.isNaN(parsed.getTime())) { notify('Enter a valid due time',true); return; } due=parsed.toISOString(); }
              value=JSON.stringify({title:value,due,calendarID});
            }
          }
          if(moduleID==='reminders'&&actionID==='addList') {
            value=prompt('New Reminders list name'); if(!value||!value.trim()) return; value=value.trim();
          }
          if(moduleID==='calendar'&&actionID==='add') {
            const title=prompt('Event title'); if(!title||!title.trim()) return;
            const suggested=new Date(Date.now()+3600000); suggested.setMinutes(0,0,0);
            const pad=n=>String(n).padStart(2,'0');
            const local=`${suggested.getFullYear()}-${pad(suggested.getMonth()+1)}-${pad(suggested.getDate())} ${pad(suggested.getHours())}:${pad(suggested.getMinutes())}`;
            const startText=prompt('Start (YYYY-MM-DD HH:MM)',local); if(!startText) return;
            const start=new Date(startText.replace(' ','T')); if(Number.isNaN(start.getTime())) { notify('Enter a valid start time',true); return; }
            const minutes=Number(prompt('Duration in minutes','60')); if(!Number.isFinite(minutes)||minutes<=0) { notify('Enter a valid duration',true); return; }
            const link=(prompt('Meeting link (optional)','')||'').trim();
            const notes=(prompt('Notes (optional)','')||'').trim();
            value=JSON.stringify({title:title.trim(),start:start.toISOString(),end:new Date(start.getTime()+minutes*60000).toISOString(),joinURL:link||null,notes:notes||null});
          }
          if(moduleID==='calendar'&&actionID==='edit') {
            let draft; try { draft=JSON.parse(actionValue||''); } catch(error) { notify('This event changed. Refresh and try again.',true); return; }
            const title=prompt('Event title',draft.title||''); if(!title||!title.trim()) return;
            const toLocal=value=>{ const date=new Date(value); const pad=n=>String(n).padStart(2,'0'); return `${date.getFullYear()}-${pad(date.getMonth()+1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}`; };
            const startText=prompt('Start (YYYY-MM-DD HH:MM)',toLocal(draft.start)); if(!startText) return;
            const endText=prompt('End (YYYY-MM-DD HH:MM)',toLocal(draft.end)); if(!endText) return;
            const start=new Date(startText.replace(' ','T')); const end=new Date(endText.replace(' ','T'));
            if(Number.isNaN(start.getTime())||Number.isNaN(end.getTime())||end<=start) { notify('Enter a valid time range',true); return; }
            const link=(prompt('Meeting link (optional)',draft.joinURL||'')||'').trim();
            const notes=(prompt('Notes (optional)',draft.notes||'')||'').trim();
            value=JSON.stringify({title:title.trim(),start:start.toISOString(),end:end.toISOString(),joinURL:link||null,notes:notes||null});
          }
          if(moduleID==='teleprompter'&&actionID==='set') {
            value=prompt('Teleprompter script'); if(!value||!value.trim()) return; value=value.trim();
          }
          if(moduleID==='notes'&&(actionID==='append'||actionID==='replace')) {
            let seed;
            if(actionID==='replace') { try { seed=JSON.parse(actionValue||''); } catch(error) { seed=null; } }
            value=prompt(actionID==='append'?'Append to note':'Edit note',actionID==='replace'?(seed?.text||payload):'');
            if(!value||!value.trim()) return; value=value.trim();
            if(actionID==='replace') value=JSON.stringify({text:value,category:seed?.category||null,baseRevision:seed?.baseRevision||null});
          }
          if(moduleID==='notes'&&actionID==='setCategory') {
            let seed; try { seed=JSON.parse(actionValue||''); } catch(error) { notify('This note changed. Refresh and try again.',true); return; }
            const category=(prompt('Category (leave blank to clear)',seed.category||'')||'').trim();
            if(category.length>40) { notify('Category is too long',true); return; }
            value=JSON.stringify({text:seed.text,category:category||null,baseRevision:seed.baseRevision});
          }
          if(moduleID==='claude'&&(actionID==='ask'||actionID==='plan')) {
            const draft=await collectClaudeDraft(actionID); if(!draft) return; value=JSON.stringify(draft);
          }
          if(moduleID==='audio'&&actionID==='setVolume') {
            const requested=prompt('Mac output volume (0–100)',actionValue||'50'); if(requested===null) return;
            const volume=Number(requested); if(!Number.isInteger(volume)||volume<0||volume>100) { notify('Choose a whole number from 0 to 100',true); return; }
            value=String(volume);
          }
          try {
            const preparedResponse=await fetch('/api/hub/actions/prepare',{method:'POST',headers:{...authHeaders(),'Content-Type':'application/json'},body:JSON.stringify({intent:{moduleID,actionID,targetID,value}})});
            const prepared=await preparedResponse.json(); if(!preparedResponse.ok) throw new Error(prepared.error||'Action is unavailable');
            if(!confirm(prepared.preview)) return;
            const executeResponse=await fetch('/api/hub/actions/execute',{method:'POST',headers:{...authHeaders(),'Content-Type':'application/json'},body:JSON.stringify({intent:prepared.intent,actionToken:prepared.actionToken})});
            const result=await executeResponse.json(); if(!executeResponse.ok) throw new Error(result.error||'Action failed');
            notify(result.message); await refreshHub();
          } catch(error) { notify(error.message,true); }
        }

        async function refreshHub() {
          if(mediaSeekState.active) return;
          const response=await fetch('/api/hub/snapshot',{method:'POST',headers:{...authHeaders(),'Content-Type':'application/json'},cache:'no-store',body:JSON.stringify({requestedMode:selectedMode,calendarReferenceDate,calendarSelectedDate})});
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
          if(!deviceToken) { pair.classList.remove('hidden'); approvals.innerHTML=''; questions.innerHTML=''; hub.innerHTML=''; hubConfig.innerHTML=''; hubConfig.classList.add('hidden'); modes.classList.add('hidden'); hubTitle.classList.add('hidden'); approvalTitle.classList.add('hidden'); questionTitle.classList.add('hidden'); empty.classList.add('hidden'); setStatus('Pairing required'); return; }
          try {
            const response=await fetch('/api/approvals',{headers:authHeaders(),cache:'no-store'});
            if(response.status===401) { deviceToken=''; localStorage.removeItem(tokenKey); pair.classList.remove('hidden'); setStatus('Pairing required'); return; }
            const body=await response.json(); if(!response.ok) throw new Error(body.error||'Mac unavailable');
            pair.classList.add('hidden'); render(body.approvals||[]); renderQuestions(body.questions||[]); await refreshHub(); setStatus(`${(body.approvals||[]).length+(body.questions||[]).length} waiting`,true);
          } catch(error) { setStatus('Mac offline'); }
        }

        function userIsEditing() {
          const active=document.activeElement;
          return Boolean(
            claudeInput.resolve
            || mediaSeekState.active
            || (active&&active.matches('input:not([type="range"]),textarea,select,[contenteditable="true"]'))
          );
        }

        document.getElementById('pairButton').addEventListener('click',pairDevice);
        document.getElementById('code').addEventListener('keydown',event=>{if(event.key==='Enter')pairDevice();});
        modes.querySelectorAll('[data-mode]').forEach(button=>button.addEventListener('click',()=>setMode(button.dataset.mode)));
        mediaPreflightDone.addEventListener('click',closeMediaPreflight);
        claudeHold.addEventListener('pointerdown',event=>{event.preventDefault();claudeHold.setPointerCapture?.(event.pointerId);startClaudeSpeech(false);});
        ['pointerup','pointercancel','pointerleave'].forEach(name=>claudeHold.addEventListener(name,()=>{if(claudeInput.recognition)stopClaudeSpeech('Voice stopped. Review the transcript before continuing.');}));
        claudeContinuous.addEventListener('click',()=>{if(claudeInput.recognition)stopClaudeSpeech('Voice stopped. Review the transcript before continuing.');else startClaudeSpeech(true);});
        claudeFiles.addEventListener('change',async()=>{
          try { claudeInput.contexts=await loadClaudeFiles(Array.from(claudeFiles.files||[])); updateClaudeContextSummary(); }
          catch(error) { claudeInput.contexts=[]; claudeFiles.value=''; updateClaudeContextSummary(); notify(error.message,true); }
        });
        document.getElementById('claudeCancel').addEventListener('click',()=>closeClaudeComposer(null));
        document.getElementById('claudeReview').addEventListener('click',()=>{
          const prompt=claudePrompt.value.trim(); if(!prompt) { claudePrompt.focus(); return; }
          closeClaudeComposer({prompt,contexts:claudeInput.contexts});
        });
        if('serviceWorker' in navigator) navigator.serviceWorker.register('/sw.js').catch(()=>{});
        refresh(); setInterval(()=>{if(document.visibilityState==='visible'&&!userIsEditing())refresh();},4000);
        document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='hidden'){closeMediaPreflight();closeClaudeComposer(null);}else refresh();});
        window.addEventListener('pagehide',()=>{releaseLocalMedia();closeClaudeComposer(null);});
      </script>
    </body>
    </html>
    """#
}
