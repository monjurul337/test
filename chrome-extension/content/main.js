/**
 * Content Script: Main Automation Orchestrator
 * Coordinates all content scripts to run the full booking automation flow.
 */

const { sleep, log, showOverlay, waitForElement } = window.VisaBotUtils;
const { fillApplicantForm, selectMission, selectIvacCenter, selectVisaDetails, uploadProfileDocuments, clickNext } = window.VisaBotFormFiller;
const { detectPage, startBooking, acceptTerms, confirmBooking, handleCaptcha, recoverFromError } = window.VisaBotNavigator;

let automationConfig = null;
let automationRunning = false;
let stepHistory = [];

// ─── Get config from storage ──────────────────────────────────────────────────
async function loadConfig() {
  return new Promise(resolve => {
    chrome.runtime.sendMessage({ type: 'get_status' }, (response) => {
      automationConfig = response?.config || {};
      resolve(automationConfig);
    });
  });
}

// ─── Main automation flow ─────────────────────────────────────────────────────
async function runAutomation() {
  if (automationRunning) return;
  automationRunning = true;

  try {
    const config = await loadConfig();
    if (!config.botActive) {
      automationRunning = false;
      return;
    }

    const profile = config.profiles?.[config.activeProfile] || {};
    log('Starting automation flow...');
    showOverlay('🤖 Automation starting...', 'info');

    const page = detectPage();
    log(`Current page: ${page}`);
    stepHistory.push({ page, ts: Date.now() });

    const gapMs = config.gapTiming || 3000;

    switch (page) {
      case 'home': {
        showOverlay('Starting booking flow...', 'info');
        await acceptTerms();
        await sleep(gapMs);
        await startBooking();
        await sleep(gapMs);
        break;
      }

      case 'mission_select': {
        showOverlay('Selecting mission & center...', 'info');
        await selectMission(config.mission || 'Kolkata');
        await sleep(gapMs);
        await selectIvacCenter(config.ivacCenter || 'Dhaka');
        await sleep(gapMs);
        await selectVisaDetails(config.visaType || 'Tourist', config.visaCategory || 'Individual');
        await sleep(gapMs);
        await clickNext();
        break;
      }

      case 'form_fill': {
        if (!profile || Object.keys(profile).length === 0) {
          showOverlay('⚠️ No applicant profile configured. Please set up a profile in the extension popup.', 'warn');
          log('No profile configured', 'warn');
          automationRunning = false;
          return;
        }
        showOverlay('Filling applicant form...', 'info');
        await fillApplicantForm(profile);
        await sleep(gapMs);
        await clickNext();
        break;
      }

      case 'pdf_upload': {
        showOverlay('Uploading documents...', 'info');
        if (profile.documents && profile.documents.length > 0) {
          await uploadProfileDocuments(profile);
          await sleep(gapMs);
        } else {
          showOverlay('⚠️ No documents in profile. Please upload manually or add to profile.', 'warn');
          log('No documents configured', 'warn');
          automationRunning = false;
          return;
        }
        await clickNext();
        break;
      }

      case 'date_select': {
        // Slot monitoring handles this via the background alarm
        showOverlay('Monitoring for available slots...', 'info');
        const found = await window.VisaBotSlotMonitor.checkAndBook(config);
        if (found && config.autoConfirm) {
          await sleep(gapMs);
          await handleCaptcha();
          await sleep(1000);
          await clickNext();
        }
        break;
      }

      case 'otp_input': {
        showOverlay('Waiting for OTP from Android app...', 'info');
        log('Waiting for OTP...');
        // OTP handler will auto-fill when received from background SW
        break;
      }

      case 'confirm': {
        if (config.autoConfirm) {
          await sleep(gapMs);
          await handleCaptcha();
          await sleep(1000);
          await confirmBooking();
        } else {
          showOverlay('⚠️ Manual confirmation required. Auto-confirm is disabled.', 'warn');
        }
        break;
      }

      case 'success': {
        showOverlay('🎉 Appointment booked successfully!', 'success');
        log('Booking complete!');
        chrome.runtime.sendMessage({ type: 'toggle_bot', active: false });
        await captureConfirmation();
        break;
      }

      default: {
        log(`Unknown page state, waiting...`, 'warn');
        showOverlay('Analyzing page...', 'info');
        break;
      }
    }
  } catch (err) {
    log(`Automation error: ${err.message}`, 'error');
    showOverlay(`Error: ${err.message}`, 'error');
    await recoverFromError();
  } finally {
    automationRunning = false;
  }
}

/**
 * Capture the confirmation page content.
 */
async function captureConfirmation() {
  const confirmationData = {
    url: window.location.href,
    bodyText: document.body.innerText.substring(0, 500),
    timestamp: Date.now(),
  };

  // Try to find confirmation number
  const numberSelectors = ['[class*="booking-ref"]', '[class*="confirmation"]', '[id*="booking"]', 'strong', '.alert-success'];
  for (const sel of numberSelectors) {
    const el = document.querySelector(sel);
    if (el && el.textContent.match(/[A-Z0-9]{6,}/)) {
      confirmationData.bookingRef = el.textContent.trim();
      break;
    }
  }

  chrome.runtime.sendMessage({ type: 'booking_confirmed', data: confirmationData });
  log(`Booking ref: ${confirmationData.bookingRef || 'not found'}`);
}

// ─── Listen for manual triggers from popup ────────────────────────────────────
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.type === 'start_automation') {
    runAutomation();
    sendResponse({ success: true });
  }
});

// ─── Auto-run if bot is active ────────────────────────────────────────────────
(async () => {
  await sleep(2000); // Wait for page to fully load
  const config = await loadConfig();
  if (config.botActive) {
    log('Bot is active. Running automation...');
    runAutomation();
  } else {
    log('Bot is inactive. Waiting for activation.');
    showOverlay('IVAC Visa Bot ready. Click bottom-right corner button to open controls.', 'info');
  }
})();
