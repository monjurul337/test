class ColabAutopilot {
  static const String keepAliveScript = '''
(function() {
  if (window.__mhKeepAliveInstalled) return;
  window.__mhKeepAliveInstalled = true;
  setInterval(() => {
    try {
      const btn = document.querySelector('#top-toolbar colab-connect-button')?.shadowRoot?.querySelector('#connect');
      if (btn && /reconnect/i.test(btn.innerText || '')) {
        btn.click();
      }
      document.dispatchEvent(new MouseEvent('mousemove', { bubbles: true, clientX: 12, clientY: 12 }));
    } catch (e) {}
  }, 30000);
})();
''';

  static const String autoRunCellScript = '''
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
''';
}
