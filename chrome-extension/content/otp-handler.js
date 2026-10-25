/**
 * Content Script: OTP Handler
 * Listens for OTP messages from the background service worker and auto-fills OTP fields.
 */

const { waitForElement, sleep, typeInto, findButtonByText, log, showOverlay } = window.VisaBotUtils;

let pendingOTP = null;

// ─── Listen for OTP from background SW ───────────────────────────────────────
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.type === 'otp_received') {
    const { otp, sender: smsSender, rawMessage } = msg;
    log(`OTP received: ${otp} from ${smsSender}`);
    showOverlay(`OTP received: <strong>${otp}</strong><br><small>From: ${smsSender}</small>`, 'success');
    pendingOTP = otp;
    tryFillOTP(otp);
    sendResponse({ success: true });
  }
});

/**
 * Try to find and fill OTP input fields on the current page.
 */
async function tryFillOTP(otp) {
  const otpSelectors = [
    'input[name="otp"]',
    'input[id*="otp"]',
    'input[placeholder*="OTP"]',
    'input[placeholder*="otp"]',
    'input[name*="verification"]',
    'input[type="number"][maxlength="6"]',
    'input[type="text"][maxlength="6"]',
    '.otp-input',
    '#otp',
  ];

  for (const sel of otpSelectors) {
    const input = document.querySelector(sel);
    if (input && input.offsetParent !== null) {
      typeInto(input, otp);
      log(`OTP auto-filled in: ${sel}`);
      showOverlay(`OTP <strong>${otp}</strong> auto-filled! Submitting...`, 'success');
      await sleep(800);
      await submitOTPForm(input);
      return;
    }
  }

  // If no field found yet, set up observer to catch dynamically loaded OTP fields
  log('OTP field not found, setting up observer...', 'warn');
  observeForOTPField(otp);
}

/**
 * Watch for OTP input fields to appear (e.g., after modal opens).
 */
function observeForOTPField(otp) {
  const observer = new MutationObserver(async (mutations) => {
    const otpSelectors = [
      'input[name="otp"]', 'input[id*="otp"]',
      'input[placeholder*="OTP"]', 'input[type="number"][maxlength="6"]',
    ];
    for (const sel of otpSelectors) {
      const input = document.querySelector(sel);
      if (input && input.offsetParent !== null) {
        observer.disconnect();
        await sleep(300);
        typeInto(input, otp);
        log(`OTP auto-filled (observer): ${sel}`);
        showOverlay(`OTP <strong>${otp}</strong> auto-filled! Submitting...`, 'success');
        await sleep(800);
        await submitOTPForm(input);
        return;
      }
    }
  });
  observer.observe(document.body, { childList: true, subtree: true, attributes: true });

  // Stop observing after 60 seconds
  setTimeout(() => observer.disconnect(), 60000);
}

/**
 * Submit the OTP form after filling.
 */
async function submitOTPForm(inputEl) {
  // Try finding submit button near the OTP field
  const form = inputEl.closest('form');
  if (form) {
    const submitBtn = form.querySelector('button[type="submit"], input[type="submit"]');
    if (submitBtn) {
      submitBtn.click();
      log('OTP form submitted via submit button');
      return;
    }
    // Try form.submit()
    try {
      form.submit();
      log('OTP form submitted via form.submit()');
      return;
    } catch (e) {}
  }

  // Look for common submit buttons
  const submitTexts = ['verify', 'submit', 'confirm', 'ok', 'proceed'];
  for (const text of submitTexts) {
    const btn = findButtonByText(text);
    if (btn && btn.offsetParent !== null) {
      btn.click();
      log(`OTP form submitted via "${text}" button`);
      return;
    }
  }

  log('Could not find submit button after OTP fill', 'warn');
}

// ─── Export pending OTP for other scripts ─────────────────────────────────────
window.VisaBotOTP = {
  getPending: () => pendingOTP,
  clearPending: () => { pendingOTP = null; },
};
