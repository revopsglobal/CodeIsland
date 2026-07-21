import Foundation

enum TelegramApprovalWebApp {
    static let html = #"""
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
      <meta name="color-scheme" content="light dark">
      <title>CodeIsland secure review</title>
      <script src="https://telegram.org/js/telegram-web-app.js"></script>
      <style>
        :root {
          color-scheme: light dark;
          font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
          --surface: var(--tg-theme-bg-color, #f5f4ef);
          --card: var(--tg-theme-secondary-bg-color, rgba(255, 255, 255, .82));
          --text: var(--tg-theme-text-color, #171714);
          --muted: var(--tg-theme-hint-color, #6e6d68);
          --accent: var(--tg-theme-button-color, #007aff);
          --accent-text: var(--tg-theme-button-text-color, #ffffff);
          --danger: var(--tg-theme-destructive-text-color, #ff3b30);
          --line: color-mix(in srgb, var(--text) 12%, transparent);
        }
        * { box-sizing: border-box; }
        body {
          margin: 0;
          min-height: 100vh;
          background: var(--surface);
          color: var(--text);
          padding: calc(18px + env(safe-area-inset-top)) 16px calc(18px + env(safe-area-inset-bottom));
          -webkit-font-smoothing: antialiased;
        }
        main { width: min(100%, 560px); margin: 0 auto; }
        .eyebrow {
          margin: 0 0 9px;
          color: var(--muted);
          font-size: 12px;
          font-weight: 700;
          letter-spacing: .12em;
          text-transform: uppercase;
        }
        h1 { margin: 0; font-size: clamp(26px, 7vw, 36px); line-height: 1.08; letter-spacing: -.035em; }
        .summary { margin: 12px 0 0; color: var(--muted); font-size: 16px; line-height: 1.45; }
        .card {
          margin-top: 18px;
          padding: 18px;
          border: 1px solid var(--line);
          border-radius: 20px;
          background: var(--card);
          box-shadow: 0 12px 40px rgba(0, 0, 0, .07);
          backdrop-filter: blur(22px) saturate(140%);
        }
        .label { color: var(--muted); font-size: 12px; font-weight: 700; letter-spacing: .08em; text-transform: uppercase; }
        .risk-value { margin: 8px 0 4px; font-size: 18px; font-weight: 700; text-transform: capitalize; }
        .risk-reason { margin: 0; color: var(--muted); line-height: 1.45; }
        .risk-destructive { color: var(--danger); }
        ul { margin: 10px 0 0; padding-left: 20px; }
        li + li { margin-top: 7px; }
        details { margin-top: 18px; border-top: 1px solid var(--line); padding-top: 14px; }
        summary { min-height: 44px; display: flex; align-items: center; cursor: pointer; font-weight: 650; }
        .detail-row { padding: 12px 0; border-top: 1px solid var(--line); }
        .detail-label { display: block; color: var(--muted); font-size: 12px; font-weight: 650; }
        code { display: block; margin-top: 5px; white-space: pre-wrap; overflow-wrap: anywhere; font: 13px/1.45 ui-monospace, "SFMono-Regular", Menlo, monospace; }
        .fingerprint { margin-top: 16px; color: var(--muted); font: 12px ui-monospace, "SFMono-Regular", Menlo, monospace; }
        .actions { display: grid; grid-template-columns: 1fr 1.35fr; gap: 10px; margin-top: 18px; }
        button {
          min-height: 44px;
          border: 0;
          border-radius: 14px;
          padding: 11px 14px;
          font: inherit;
          font-weight: 700;
          cursor: pointer;
        }
        button:disabled { opacity: .45; cursor: wait; }
        button:focus-visible, summary:focus-visible { outline: 3px solid color-mix(in srgb, var(--accent) 55%, transparent); outline-offset: 3px; }
        #deny { background: color-mix(in srgb, var(--danger) 12%, transparent); color: var(--danger); }
        #approve, #confirm { background: var(--accent); color: var(--accent-text); }
        #cancel { background: var(--card); color: var(--text); }
        #status { min-height: 24px; margin: 14px 2px 0; color: var(--muted); line-height: 1.4; }
        dialog { width: min(calc(100% - 32px), 430px); border: 1px solid var(--line); border-radius: 20px; padding: 20px; background: var(--surface); color: var(--text); }
        dialog::backdrop { background: rgba(0, 0, 0, .42); backdrop-filter: blur(5px); }
        dialog h2 { margin: 0; font-size: 22px; }
        dialog p { color: var(--muted); line-height: 1.45; }
        .dialog-actions { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-top: 18px; }
        [hidden] { display: none !important; }
        @media (prefers-reduced-motion: reduce) { *, *::before, *::after { scroll-behavior: auto !important; transition: none !important; } }
      </style>
    </head>
    <body>
      <main>
        <p class="eyebrow">CodeIsland · secure review</p>
        <section id="summary" aria-labelledby="headline">
          <h1 id="headline">Verifying request…</h1>
          <p id="summaryText" class="summary">Confirming this Telegram session with your Mac.</p>
        </section>

        <section class="card" id="approvalCard" hidden>
          <div id="risk">
            <span class="label">Risk</span>
            <p id="riskValue" class="risk-value"></p>
            <p id="riskReason" class="risk-reason"></p>
          </div>

          <div id="scope">
            <p class="label">Changed scope</p>
            <ul id="scopeList"></ul>
          </div>

          <details id="details">
            <summary>Show exact details</summary>
            <div id="detailList"></div>
          </details>

          <p class="fingerprint">Action fingerprint: <strong id="fingerprint"></strong></p>
          <div class="actions" id="actions">
            <button id="deny" type="button">Deny</button>
            <button id="approve" type="button">Approve once</button>
          </div>
        </section>
        <p id="status" role="status" aria-live="polite"></p>
      </main>

      <dialog id="confirmDialog" aria-labelledby="confirmTitle">
        <h2 id="confirmTitle">Confirm decision</h2>
        <p id="confirmCopy"></p>
        <p class="fingerprint">Fingerprint: <strong id="confirmFingerprint"></strong></p>
        <div class="dialog-actions">
          <button id="cancel" type="button">Cancel</button>
          <button id="confirm" type="button">Confirm</button>
        </div>
      </dialog>

      <script>
        (() => {
          'use strict';
          const tg = window.Telegram && window.Telegram.WebApp;
          const launchNonce = new URLSearchParams(window.location.search).get('launch');
          const state = { model: null, decision: null };
          const byId = (id) => document.getElementById(id);
          const setText = (id, value) => { byId(id).textContent = value || ''; };

          function fail(message) {
            setText('headline', 'Unable to verify this request');
            setText('summaryText', message);
            setText('status', 'Open the newest CodeIsland Telegram alert and try again.');
            byId('approvalCard').hidden = true;
          }

          async function postJSON(path, body) {
            const response = await fetch(path, {
              method: 'POST',
              headers: {'Content-Type': 'application/json'},
              credentials: 'same-origin',
              cache: 'no-store',
              body: JSON.stringify(body)
            });
            const payload = await response.json().catch(() => ({}));
            if (!response.ok) throw new Error(payload.error || 'Secure request failed');
            return payload;
          }

          function render(model) {
            state.model = model;
            setText('headline', model.headline);
            setText('summaryText', model.summary);
            setText('riskValue', model.risk);
            setText('riskReason', model.riskReason);
            setText('fingerprint', model.fingerprint);
            byId('riskValue').className = `risk-value risk-${model.risk}`;

            const scopeItems = (model.changedScope || []).map((value) => {
              const item = document.createElement('li');
              item.textContent = value;
              return item;
            });
            byId('scopeList').replaceChildren(...scopeItems);

            const detailRows = (model.details || []).map((detail) => {
              const row = document.createElement('div');
              row.className = 'detail-row';
              const label = document.createElement('span');
              label.className = 'detail-label';
              label.textContent = detail.label;
              const value = document.createElement('code');
              value.textContent = detail.value;
              row.append(label, value);
              return row;
            });
            byId('detailList').replaceChildren(...detailRows);
            byId('approvalCard').hidden = false;
            setText('status', 'Nothing happens until you confirm a decision.');
          }

          function openConfirmation(decision) {
            if (!state.model) return;
            state.decision = decision;
            setText('confirmTitle', decision === 'approve' ? 'Approve once?' : 'Deny this action?');
            setText('confirmCopy', decision === 'approve'
              ? 'CodeIsland will allow only this exact pending action.'
              : 'CodeIsland will stop this exact pending action.');
            setText('confirmFingerprint', state.model.fingerprint);
            setText('confirm', decision === 'approve' ? 'Approve once' : 'Deny');
            byId('confirmDialog').showModal();
          }

          async function decide() {
            const model = state.model;
            if (!model || !state.decision) return;
            byId('confirm').disabled = true;
            byId('approve').disabled = true;
            byId('deny').disabled = true;
            setText('status', 'Sending your decision securely…');
            try {
              const result = await postJSON(
                `/api/telegram/approvals/${encodeURIComponent(model.requestID)}/decision`,
                {
                  initData: Telegram.WebApp.initData,
                  launchNonce,
                  sessionNonce: model.sessionNonce,
                  actionToken: model.actionToken,
                  decision: state.decision
                }
              );
              byId('confirmDialog').close();
              byId('actions').hidden = true;
              setText('status', result.message || 'Decision applied on your Mac.');
              if (tg) tg.HapticFeedback.notificationOccurred('success');
            } catch (error) {
              byId('confirmDialog').close();
              byId('confirm').disabled = false;
              byId('approve').disabled = false;
              byId('deny').disabled = false;
              setText('status', error.message || 'Decision could not be applied.');
              if (tg) tg.HapticFeedback.notificationOccurred('error');
            }
          }

          byId('approve').addEventListener('click', () => openConfirmation('approve'));
          byId('deny').addEventListener('click', () => openConfirmation('deny'));
          byId('cancel').addEventListener('click', () => byId('confirmDialog').close());
          byId('confirm').addEventListener('click', decide);

          async function start() {
            if (!tg || !launchNonce || !Telegram.WebApp.initData) {
              fail('This secure link must be opened from your private Telegram chat.');
              return;
            }
            tg.ready();
            tg.expand();
            try {
              const model = await postJSON('/api/telegram/session', {
                initData: Telegram.WebApp.initData,
                launchNonce
              });
              render(model);
            } catch (error) {
              fail(error.message || 'The link is invalid, expired, or already resolved.');
            }
          }

          start();
        })();
      </script>
    </body>
    </html>
    """#
}
