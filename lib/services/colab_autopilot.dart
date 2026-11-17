class ColabAutopilot {
  static const String keepAliveScript = r"""
(function() {
  if (window.__mhKeepAliveInstalled) return;
  window.__mhKeepAliveInstalled = true;
  let lastAlertAt = 0;

  function notifyDisconnect(reason) {
    const now = Date.now();
    if (now - lastAlertAt < 25000) return;
    lastAlertAt = now;
    try {
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler('onColabDisconnected', reason);
      }
    } catch (e) {}
  }

  setInterval(() => {
    try {
      // 1. Check top toolbar connect/reconnect button
      const conn = document.querySelector('#top-toolbar colab-connect-button');
      const btn = conn && conn.shadowRoot ? conn.shadowRoot.querySelector('#connect') : null;
      const txt = (btn && btn.innerText) ? btn.innerText.trim() : '';
      if (btn && /reconnect/i.test(txt)) {
        notifyDisconnect('Colab runtime disconnected — auto-reconnecting');
        btn.click();
      }

      // 2. Check idle / disconnected dialogs ("Are you still there?", "Runtime disconnected")
      const dialogs = document.querySelectorAll('mwc-dialog, md-dialog, paper-dialog, colab-dialog, [role="dialog"]');
      for (const d of dialogs) {
        const dt = (d.innerText || '').trim();
        if (/disconnected|still there|timed out|inactive/i.test(dt)) {
          notifyDisconnect('Colab idle/disconnect dialog detected');
          const btns = d.querySelectorAll('button, mwc-button, paper-button');
          for (const b of btns) {
            if (/reconnect|yes|ok|connect/i.test(b.innerText || '')) {
              b.click();
              break;
            }
          }
        }
      }

      // 3. Keep session active
      document.dispatchEvent(new MouseEvent('mousemove', { bubbles: true, clientX: 14, clientY: 14 }));
    } catch (e) {}
  }, 10000);
})();
""";

  static const String autoRunCellScript = r"""
(function() {
  const runBtn = document.querySelector('colab-run-button');
  if (runBtn) {
    const inner = runBtn.shadowRoot ? runBtn.shadowRoot.querySelector('button, #run-button') : runBtn;
    if (inner) { inner.click(); return 'Clicked Colab Run Cell'; }
    runBtn.click();
    return 'Clicked colab-run-button';
  }
  return 'Run button not found yet';
})();
""";
}
