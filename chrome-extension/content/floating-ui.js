/**
 * Content Script: In-Page Corner Button & Floating Control Center
 * Injects a floating launcher button on the corner of the IVAC portal page
 * that opens a sleek in-page automation control dashboard.
 */

(function () {
  if (window.__visabot_floating_ui_injected) return;
  window.__visabot_floating_ui_injected = true;

  let isPanelOpen = false;
  let botActive = false;
  let pairingCode = '------';
  let phoneConnected = false;
  let serverConnected = false;
  let currentLogs = [];

  // Default mission list
  const MISSIONS = [
    { id: 'Dhaka', name: 'Dhaka (High Commission)' },
    { id: 'Chittagong', name: 'Chittagong (Assistant HC)' },
    { id: 'Rajshahi', name: 'Rajshahi (Assistant HC)' },
    { id: 'Sylhet', name: 'Sylhet (Assistant HC)' },
    { id: 'Khulna', name: 'Khulna (Assistant HC)' }
  ];

  const IVAC_CENTERS = [
    'Dhaka (Jamuna Future Park)',
    'Chittagong',
    'Rajshahi',
    'Sylhet',
    'Khulna',
    'Barisal',
    'Jessore',
    'Mymensingh',
    'Rangpur',
    'Comilla',
    'Brahmanbaria',
    'Noakhali',
    'Thakurgaon',
    'Bogura',
    'Kushtia'
  ];

  function createFloatingUI() {
    // 1. Create Corner Button Container
    const container = document.createElement('div');
    container.id = 'visabot-corner-btn-container';

    container.innerHTML = `
      <button id="visabot-corner-btn" title="Toggle IVAC Visa Bot (Alt+V)">
        <span class="visabot-corner-icon">🤖</span>
        <span class="visabot-corner-text">IVAC Bot</span>
        <span class="visabot-corner-badge inactive" id="visabot-corner-badge">
          <span class="visabot-pulse-dot inactive" id="visabot-pulse-dot"></span>
          <span id="visabot-corner-status-txt">IDLE</span>
        </span>
      </button>
    `;

    // 2. Create Floating Panel Drawer
    const panel = document.createElement('div');
    panel.id = 'visabot-inpage-panel';

    panel.innerHTML = `
      <div class="visabot-panel-header">
        <div class="visabot-header-left">
          <span style="font-size: 20px;">🛡️</span>
          <div>
            <div class="visabot-header-title">IVAC Visa Bot Control</div>
            <div style="font-size: 11px; color: #94a3b8;" id="visabot-panel-substatus">Page: Initializing...</div>
          </div>
        </div>
        <div class="visabot-header-actions">
          <button class="visabot-btn-icon" id="visabot-btn-refresh" title="Refresh Status">🔄</button>
          <button class="visabot-btn-icon" id="visabot-btn-close" title="Close Panel">✖</button>
        </div>
      </div>

      <!-- Quick Status Strip -->
      <div class="visabot-status-strip">
        <div class="visabot-strip-item">
          <span style="color: #94a3b8;">Pairing Code:</span>
          <span class="visabot-code-pill" id="visabot-strip-code">------</span>
          <button class="visabot-btn-icon" id="visabot-btn-copy-code" style="width:20px;height:20px;font-size:10px;" title="Copy Code">📋</button>
        </div>
        <div class="visabot-strip-item">
          <span style="color: #94a3b8;">Phone:</span>
          <span id="visabot-strip-phone" style="font-weight:600;color:#94a3b8;">⚪ Waiting</span>
        </div>
      </div>

      <!-- Tab Buttons -->
      <div class="visabot-tabs">
        <div class="visabot-tab active" data-tab="tab-control">🚀 Controls</div>
        <div class="visabot-tab" data-tab="tab-otp">📱 Phone OTP</div>
        <div class="visabot-tab" data-tab="tab-profile">👤 Profile</div>
        <div class="visabot-tab" data-tab="tab-logs">📜 Logs</div>
      </div>

      <!-- Panel Body -->
      <div class="visabot-panel-body">
        
        <!-- Tab 1: Control & Booking -->
        <div class="visabot-tab-pane active" id="tab-control">
          <div class="visabot-cta-box">
            <button class="visabot-cta-btn start" id="visabot-main-toggle">
              <span>▶ START AUTOMATION</span>
            </button>
            <div style="font-size: 11px; color: #94a3b8; margin-top: 8px;">
              Auto-fills form, scans dates every 20s & submits OTP automatically
            </div>
          </div>

          <div class="visabot-form-group">
            <label class="visabot-form-label">Mission / High Commission</label>
            <select class="visabot-form-select" id="visabot-input-mission">
              ${MISSIONS.map(m => `<option value="${m.id}">${m.name}</option>`).join('')}
            </select>
          </div>

          <div class="visabot-form-group">
            <label class="visabot-form-label">Target IVAC Center</label>
            <select class="visabot-form-select" id="visabot-input-center">
              ${IVAC_CENTERS.map(c => `<option value="${c}">${c}</option>`).join('')}
            </select>
          </div>

          <div style="display: flex; gap: 10px;">
            <div class="visabot-form-group" style="flex: 1;">
              <label class="visabot-form-label">Visa Type</label>
              <select class="visabot-form-select" id="visabot-input-visa-type">
                <option value="Tourist">Tourist</option>
                <option value="Medical">Medical</option>
                <option value="Business">Business</option>
                <option value="Entry">Entry</option>
              </select>
            </div>
            <div class="visabot-form-group" style="flex: 1;">
              <label class="visabot-form-label">Check Interval</label>
              <select class="visabot-form-select" id="visabot-input-interval">
                <option value="15">15 Seconds</option>
                <option value="20" selected>20 Seconds</option>
                <option value="30">30 Seconds</option>
              </select>
            </div>
          </div>

          <div style="margin-top: 10px; display: flex; align-items: center; justify-content: space-between;">
            <label style="font-size: 12px; color: #cbd5e1; cursor: pointer;">
              <input type="checkbox" id="visabot-input-auto-confirm" checked style="accent-color: #4ade80;"> Auto-confirm Booking
            </label>
            <button class="visabot-form-select" id="visabot-btn-trigger-now" style="width: auto; padding: 6px 12px; background: rgba(74,222,128,0.2); border-color:#4ade80; cursor: pointer; color: #4ade80; font-weight: 600;">
              ⚡ Run Step Now
            </button>
          </div>
        </div>

        <!-- Tab 2: Phone OTP -->
        <div class="visabot-tab-pane" id="tab-otp">
          <div class="visabot-otp-card">
            <div style="font-size: 11px; text-transform: uppercase; color: #94a3b8; letter-spacing: 1px;">Latest OTP Received</div>
            <div class="visabot-otp-display" id="visabot-display-otp">------</div>
            <div style="font-size: 11px; color: #64748b;" id="visabot-otp-timestamp">Waiting for incoming SMS from Android app...</div>
          </div>

          <div class="visabot-form-group">
            <label class="visabot-form-label">Pairing Instructions</label>
            <div style="background: rgba(19, 29, 52, 0.6); padding: 12px; border-radius: 8px; font-size: 12px; line-height: 1.6; color: #cbd5e1;">
              1. Open the <strong>IVAC Visa Bot</strong> Android APK.<br>
              2. Enter Pairing Code: <strong style="color: #4ade80;" id="visabot-guide-code">------</strong><br>
              3. Tap <strong>Start Service</strong>. When an SMS arrives from IVAC, it will instantly auto-fill on this page.
            </div>
          </div>

          <div style="display: flex; gap: 8px; margin-top: 10px;">
            <button class="visabot-form-select" id="visabot-btn-test-otp" style="flex: 1; cursor: pointer; background: rgba(99,102,241,0.2); border-color: #818cf8; color: #818cf8;">
              🧪 Simulate Test OTP
            </button>
            <button class="visabot-form-select" id="visabot-btn-reset-session" style="flex: 1; cursor: pointer; background: rgba(248,113,113,0.15); border-color: #f87171; color: #f87171;">
              🔄 New Pairing Code
            </button>
          </div>
        </div>

        <!-- Tab 3: Profile -->
        <div class="visabot-tab-pane" id="tab-profile">
          <div class="visabot-form-group">
            <label class="visabot-form-label">Web File Number (e.g., BGDD00000000)</label>
            <input type="text" class="visabot-form-input" id="visabot-prof-webfile" placeholder="BGDD12345678">
          </div>
          <div class="visabot-form-group">
            <label class="visabot-form-label">Passport Number</label>
            <input type="text" class="visabot-form-input" id="visabot-prof-passport" placeholder="A01234567">
          </div>
          <div class="visabot-form-group">
            <label class="visabot-form-label">Applicant Full Name</label>
            <input type="text" class="visabot-form-input" id="visabot-prof-name" placeholder="Rahim Ahmed">
          </div>
          <div style="display: flex; gap: 10px;">
            <div class="visabot-form-group" style="flex: 1;">
              <label class="visabot-form-label">Mobile Phone</label>
              <input type="text" class="visabot-form-input" id="visabot-prof-phone" placeholder="01700000000">
            </div>
            <div class="visabot-form-group" style="flex: 1;">
              <label class="visabot-form-label">Email</label>
              <input type="email" class="visabot-form-input" id="visabot-prof-email" placeholder="rahim@gmail.com">
            </div>
          </div>
          <button class="visabot-form-select" id="visabot-btn-save-profile" style="cursor: pointer; background: #22c55e; border-color: #22c55e; color: #ffffff; font-weight: 700; padding: 10px;">
            💾 Save Profile Details
          </button>
        </div>

        <!-- Tab 4: Logs -->
        <div class="visabot-tab-pane" id="tab-logs">
          <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px;">
            <span style="font-size: 11px; text-transform: uppercase; color: #94a3b8;">Real-time Activity Stream</span>
            <button id="visabot-btn-clear-logs" style="background: none; border: none; color: #64748b; font-size: 11px; cursor: pointer;">Clear</button>
          </div>
          <div class="visabot-logs-terminal" id="visabot-logs-feed">
            <div class="visabot-log-entry visabot-log-info">
              <span class="visabot-log-time">[Ready]</span> IVAC Bot Interface loaded in page corner.
            </div>
          </div>
        </div>

      </div>
    `;

    document.body.appendChild(container);
    document.body.appendChild(panel);

    bindEvents();
    syncInitialState();
    startPageDetector();
  }

  function bindEvents() {
    const cornerBtn = document.getElementById('visabot-corner-btn');
    const panel = document.getElementById('visabot-inpage-panel');
    const closeBtn = document.getElementById('visabot-btn-close');
    const refreshBtn = document.getElementById('visabot-btn-refresh');
    const mainToggle = document.getElementById('visabot-main-toggle');
    const copyCodeBtn = document.getElementById('visabot-btn-copy-code');
    const triggerNowBtn = document.getElementById('visabot-btn-trigger-now');
    const testOtpBtn = document.getElementById('visabot-btn-test-otp');
    const resetSessionBtn = document.getElementById('visabot-btn-reset-session');
    const saveProfileBtn = document.getElementById('visabot-btn-save-profile');
    const clearLogsBtn = document.getElementById('visabot-btn-clear-logs');

    // Toggle panel
    cornerBtn.addEventListener('click', () => togglePanel());
    closeBtn.addEventListener('click', () => togglePanel(false));

    // Tab switching
    document.querySelectorAll('.visabot-tab').forEach(tab => {
      tab.addEventListener('click', () => {
        document.querySelectorAll('.visabot-tab').forEach(t => t.classList.remove('active'));
        document.querySelectorAll('.visabot-tab-pane').forEach(p => p.classList.remove('active'));
        tab.classList.add('active');
        const target = document.getElementById(tab.dataset.tab);
        if (target) target.classList.add('active');
      });
    });

    // Main Bot Toggle (Start / Stop)
    mainToggle.addEventListener('click', () => {
      botActive = !botActive;
      updateBotActiveUI(botActive);
      chrome.runtime.sendMessage({ type: 'toggle_bot', active: botActive });
      if (botActive) {
        addLog('Bot activated by user. Running automation loop...', 'success');
        chrome.runtime.sendMessage({ type: 'start_automation' });
      } else {
        addLog('Bot paused by user.', 'warn');
      }
    });

    // Copy Pairing Code
    copyCodeBtn.addEventListener('click', () => {
      if (pairingCode && pairingCode !== '------') {
        navigator.clipboard.writeText(pairingCode);
        copyCodeBtn.textContent = '✓';
        setTimeout(() => { copyCodeBtn.textContent = '📋'; }, 1500);
      }
    });

    // Run Step Now
    triggerNowBtn.addEventListener('click', () => {
      addLog('Manual step execution triggered...', 'info');
      chrome.runtime.sendMessage({ type: 'start_automation' });
    });

    // Refresh Status
    refreshBtn.addEventListener('click', () => {
      syncInitialState();
    });

    // Simulate Test OTP
    testOtpBtn.addEventListener('click', () => {
      const mockOtp = String(Math.floor(100000 + Math.random() * 900000));
      addLog(`Testing OTP pipeline with mock code: ${mockOtp}`, 'warn');
      window.postMessage({ type: 'visabot_mock_otp', otp: mockOtp }, '*');
      chrome.runtime.sendMessage({
        type: 'otp_received',
        otp: mockOtp,
        sender: 'IVAC-TEST',
        rawMessage: `Your IVAC OTP is ${mockOtp}. Do not share.`
      });
    });

    // Reset Session
    resetSessionBtn.addEventListener('click', () => {
      if (confirm('Generate a brand new pairing code? You will need to enter it on the Android app.')) {
        chrome.runtime.sendMessage({ type: 'reset_session' }, () => {
          setTimeout(syncInitialState, 800);
        });
      }
    });

    // Save Profile Details
    saveProfileBtn.addEventListener('click', () => {
      const profileData = {
        webFileNumber: document.getElementById('visabot-prof-webfile').value.trim(),
        passportNumber: document.getElementById('visabot-prof-passport').value.trim(),
        name: document.getElementById('visabot-prof-name').value.trim(),
        phone: document.getElementById('visabot-prof-phone').value.trim(),
        email: document.getElementById('visabot-prof-email').value.trim(),
      };
      chrome.storage.local.get(['profiles', 'activeProfile'], (res) => {
        const profiles = res.profiles || {};
        const active = res.activeProfile || 'default';
        profiles[active] = { ...(profiles[active] || {}), ...profileData };
        chrome.storage.local.set({ profiles }, () => {
          saveProfileBtn.textContent = '✓ Saved Successfully!';
          setTimeout(() => { saveProfileBtn.textContent = '💾 Save Profile Details'; }, 2000);
          addLog('Applicant profile details updated.', 'success');
        });
      });
    });

    // Clear logs
    clearLogsBtn.addEventListener('click', () => {
      const feed = document.getElementById('visabot-logs-feed');
      if (feed) feed.innerHTML = '';
    });

    // Input changes persist config
    ['visabot-input-mission', 'visabot-input-center', 'visabot-input-visa-type', 'visabot-input-interval', 'visabot-input-auto-confirm'].forEach(id => {
      const el = document.getElementById(id);
      if (el) {
        el.addEventListener('change', () => {
          const cfg = {
            mission: document.getElementById('visabot-input-mission').value,
            ivacCenter: document.getElementById('visabot-input-center').value,
            visaType: document.getElementById('visabot-input-visa-type').value,
            checkInterval: parseInt(document.getElementById('visabot-input-interval').value, 10),
            autoConfirm: document.getElementById('visabot-input-auto-confirm').checked,
          };
          chrome.storage.local.set(cfg);
        });
      }
    });

    // Keyboard shortcut: Alt+V to toggle panel
    window.addEventListener('keydown', (e) => {
      if (e.altKey && (e.key === 'v' || e.key === 'V')) {
        togglePanel();
      }
    });
  }

  function togglePanel(open) {
    const panel = document.getElementById('visabot-inpage-panel');
    if (!panel) return;
    isPanelOpen = typeof open === 'boolean' ? open : !isPanelOpen;
    if (isPanelOpen) {
      panel.classList.add('open');
    } else {
      panel.classList.remove('open');
    }
  }

  function updateBotActiveUI(active) {
    const mainToggle = document.getElementById('visabot-main-toggle');
    const badge = document.getElementById('visabot-corner-badge');
    const pulseDot = document.getElementById('visabot-pulse-dot');
    const statusTxt = document.getElementById('visabot-corner-status-txt');

    if (active) {
      mainToggle.className = 'visabot-cta-btn stop';
      mainToggle.innerHTML = '<span>⏹ STOP AUTOMATION</span>';
      badge.className = 'visabot-corner-badge';
      pulseDot.className = 'visabot-pulse-dot';
      statusTxt.textContent = 'ACTIVE';
    } else {
      mainToggle.className = 'visabot-cta-btn start';
      mainToggle.innerHTML = '<span>▶ START AUTOMATION</span>';
      badge.className = 'visabot-corner-badge inactive';
      pulseDot.className = 'visabot-pulse-dot inactive';
      statusTxt.textContent = 'IDLE';
    }
  }

  function syncInitialState() {
    chrome.runtime.sendMessage({ type: 'get_status' }, (resp) => {
      if (!resp) return;

      botActive = !!resp.botActive;
      updateBotActiveUI(botActive);

      pairingCode = resp.pairingCode || '------';
      document.getElementById('visabot-strip-code').textContent = pairingCode;
      document.getElementById('visabot-guide-code').textContent = pairingCode;

      serverConnected = !!resp.connected;
      const phoneEl = document.getElementById('visabot-strip-phone');
      if (resp.config?.phoneConnected) {
        phoneEl.innerHTML = '<span style="color:#4ade80;">🟢 Connected</span>';
      } else {
        phoneEl.innerHTML = '<span style="color:#94a3b8;">⚪ Waiting</span>';
      }

      // Fill inputs from config
      const cfg = resp.config || {};
      if (cfg.mission) document.getElementById('visabot-input-mission').value = cfg.mission;
      if (cfg.ivacCenter) document.getElementById('visabot-input-center').value = cfg.ivacCenter;
      if (cfg.visaType) document.getElementById('visabot-input-visa-type').value = cfg.visaType;
      if (cfg.checkInterval) document.getElementById('visabot-input-interval').value = cfg.checkInterval;
      if (typeof cfg.autoConfirm !== 'undefined') {
        document.getElementById('visabot-input-auto-confirm').checked = cfg.autoConfirm;
      }

      // Profile details
      const activeProf = cfg.profiles?.[cfg.activeProfile || 'default'];
      if (activeProf) {
        if (activeProf.webFileNumber) document.getElementById('visabot-prof-webfile').value = activeProf.webFileNumber;
        if (activeProf.passportNumber) document.getElementById('visabot-prof-passport').value = activeProf.passportNumber;
        if (activeProf.name) document.getElementById('visabot-prof-name').value = activeProf.name;
        if (activeProf.phone) document.getElementById('visabot-prof-phone').value = activeProf.phone;
        if (activeProf.email) document.getElementById('visabot-prof-email').value = activeProf.email;
      }
    });
  }

  function addLog(msg, type = 'info') {
    const feed = document.getElementById('visabot-logs-feed');
    if (!feed) return;
    const now = new Date();
    const timeStr = `[${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}:${String(now.getSeconds()).padStart(2, '0')}]`;
    const item = document.createElement('div');
    item.className = `visabot-log-entry visabot-log-${type}`;
    item.innerHTML = `<span class="visabot-log-time">${timeStr}</span> ${escapeHtml(msg)}`;
    feed.appendChild(item);
    feed.scrollTop = feed.scrollHeight;
  }

  function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  function startPageDetector() {
    setInterval(() => {
      const pageEl = document.getElementById('visabot-panel-substatus');
      if (!pageEl) return;
      if (window.VisaBotNavigator && window.VisaBotNavigator.detectPage) {
        const page = window.VisaBotNavigator.detectPage();
        pageEl.textContent = `Page: ${page.toUpperCase().replace('_', ' ')}`;
      } else {
        pageEl.textContent = `Page: ${window.location.pathname}`;
      }
    }, 2000);
  }

  // ─── Listen for messages from background & other scripts ────────────────────
  chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
    if (msg.type === 'toggle_inpage_ui') {
      togglePanel();
      sendResponse({ success: true, isOpen: isPanelOpen });
    } else if (msg.type === 'otp_received') {
      const { otp, sender: smsSender } = msg;
      const otpDisplay = document.getElementById('visabot-display-otp');
      const timeDisplay = document.getElementById('visabot-otp-timestamp');
      if (otpDisplay) otpDisplay.textContent = otp;
      if (timeDisplay) timeDisplay.innerHTML = `<span style="color:#4ade80;">✓ Received at ${new Date().toLocaleTimeString()} from ${smsSender}</span>`;
      addLog(`🎯 Incoming OTP captured: ${otp} (From: ${smsSender})`, 'success');
      // Highlight corner button
      const cornerBtn = document.getElementById('visabot-corner-btn');
      if (cornerBtn) {
        cornerBtn.style.borderColor = '#38bdf8';
        cornerBtn.style.boxShadow = '0 0 25px rgba(56, 189, 248, 0.7)';
        setTimeout(() => {
          cornerBtn.style.borderColor = '';
          cornerBtn.style.boxShadow = '';
        }, 4000);
      }
    } else if (msg.type === 'ws_status') {
      const phoneEl = document.getElementById('visabot-strip-phone');
      if (phoneEl) {
        phoneEl.innerHTML = msg.connected
          ? '<span style="color:#4ade80;">🟢 Connected</span>'
          : '<span style="color:#f87171;">🔴 Disconnected</span>';
      }
      if (msg.pairingCode) {
        pairingCode = msg.pairingCode;
        document.getElementById('visabot-strip-code').textContent = pairingCode;
        document.getElementById('visabot-guide-code').textContent = pairingCode;
      }
    } else if (msg.type === 'session_status') {
      if (msg.pairingCode) {
        pairingCode = msg.pairingCode;
        document.getElementById('visabot-strip-code').textContent = pairingCode;
        document.getElementById('visabot-guide-code').textContent = pairingCode;
      }
      const phoneEl = document.getElementById('visabot-strip-phone');
      if (phoneEl) {
        phoneEl.innerHTML = msg.phoneConnected
          ? '<span style="color:#4ade80;">🟢 Phone Linked</span>'
          : '<span style="color:#94a3b8;">⚪ Waiting for App</span>';
      }
    }
  });

  // Listen for custom logger events
  window.addEventListener('visabot_log', (e) => {
    if (e.detail?.msg) {
      addLog(e.detail.msg, e.detail.level || 'info');
    }
  });

  // Init when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', createFloatingUI);
  } else {
    createFloatingUI();
  }
})();
