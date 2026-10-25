/**
 * Content Script: Navigator
 * Handles page-to-page navigation through the IVAC portal.
 */

const { sleep, click, log, showOverlay, waitForElement, findButtonByText, getPageState } = window.VisaBotUtils;

window.VisaBotNavigator = {
  /**
   * Navigate to the appointment booking start page.
   */
  async gotoStart() {
    if (!window.location.href.includes('appointment.ivacbd.com')) {
      window.location.href = 'https://appointment.ivacbd.com/';
      await sleep(3000);
    }
  },

  /**
   * Detect the current page state and return it.
   */
  detectPage() {
    const url = window.location.href;
    const text = document.body.innerText.toLowerCase();

    if (url.endsWith('/') || url.includes('home') || url.includes('index')) {
      // Check if there's an "Apply" or "New Appointment" button
      const applyBtn = findButtonByText('apply') || findButtonByText('new appointment') || findButtonByText('book');
      if (applyBtn) return 'home';
    }
    if (document.querySelector('input[name*="otp"], input[id*="otp"], #otp')) return 'otp_input';
    if (document.querySelector('input[type="file"]')) return 'pdf_upload';
    if (document.querySelector('.calendar, [class*="calendar"], [class*="datepicker"], [class*="date-picker"]')) return 'date_select';
    if (text.includes('select mission') || text.includes('high commission') || document.querySelector('select[name*="mission"]')) return 'mission_select';
    if (text.includes('applicant') || text.includes('personal info') || document.querySelector('input[name*="passport"]')) return 'form_fill';
    if (text.includes('confirm') && (text.includes('appointment') || text.includes('booking'))) return 'confirm';
    if (text.includes('success') || text.includes('booking confirmed') || text.includes('appointment confirmed')) return 'success';
    return 'unknown';
  },

  /**
   * Click the primary CTA on the home page to start booking.
   */
  async startBooking() {
    const ctas = ['apply now', 'book appointment', 'new appointment', 'apply', 'book now', 'start'];
    for (const text of ctas) {
      const btn = findButtonByText(text);
      if (btn && btn.offsetParent !== null) {
        click(btn);
        log(`Clicked CTA: "${text}"`);
        await sleep(2000);
        return true;
      }
    }

    // Try anchor links
    const links = document.querySelectorAll('a[href*="appointment"], a[href*="apply"]');
    if (links.length > 0) {
      click(links[0]);
      await sleep(2000);
      return true;
    }

    log('Could not find start booking button', 'warn');
    return false;
  },

  /**
   * Accept terms and conditions if present.
   */
  async acceptTerms() {
    const checkboxes = document.querySelectorAll('input[type="checkbox"]');
    for (const cb of checkboxes) {
      if (!cb.checked) {
        cb.click();
        await sleep(200);
      }
    }
    const agreeBtn = findButtonByText('agree') || findButtonByText('accept') || findButtonByText('i agree');
    if (agreeBtn) {
      click(agreeBtn);
      await sleep(1000);
      return true;
    }
    return false;
  },

  /**
   * Confirm the final booking.
   */
  async confirmBooking() {
    showOverlay('Confirming booking...', 'info');
    log('Confirming booking...');

    const confirmBtns = ['confirm', 'confirm booking', 'finalize', 'pay', 'submit booking'];
    for (const text of confirmBtns) {
      const btn = findButtonByText(text);
      if (btn && btn.offsetParent !== null && !btn.disabled) {
        click(btn);
        log(`Clicked confirm: "${text}"`);
        await sleep(3000);
        showOverlay('Booking confirmation submitted!', 'success');
        return true;
      }
    }
    log('Confirm button not found', 'warn');
    return false;
  },

  /**
   * Handle the captcha if present (manual override notification).
   */
  async handleCaptcha() {
    const captchaFrame = document.querySelector('iframe[src*="recaptcha"], iframe[src*="captcha"]');
    const captchaDiv = document.querySelector('.g-recaptcha, [class*="captcha"]');
    if (captchaFrame || captchaDiv) {
      showOverlay('⚠️ CAPTCHA detected! Please solve it manually.', 'warn');
      log('CAPTCHA detected - waiting for manual solve', 'warn');

      // Wait up to 3 minutes for the captcha to be solved
      return new Promise((resolve) => {
        const interval = setInterval(() => {
          // Check if captcha token is present (indicates it was solved)
          const token = document.querySelector('[name="g-recaptcha-response"]');
          if (token && token.value) {
            clearInterval(interval);
            log('Captcha solved!');
            resolve(true);
          }
        }, 2000);
        setTimeout(() => { clearInterval(interval); resolve(false); }, 180000);
      });
    }
    return true; // No captcha
  },

  /**
   * Navigate back to the start if an error occurs.
   */
  async recoverFromError() {
    log('Attempting recovery from error...', 'warn');
    showOverlay('Error detected. Restarting flow...', 'warn');
    await sleep(2000);

    const errorSelectors = ['.alert-danger, .error-message, [class*="error"]'];
    for (const sel of errorSelectors) {
      const el = document.querySelector(sel);
      if (el) {
        log(`Error text: ${el.textContent.trim()}`, 'error');
      }
    }

    // Try clicking "Back" or reloading
    const backBtn = findButtonByText('back') || findButtonByText('try again') || findButtonByText('restart');
    if (backBtn) {
      click(backBtn);
      await sleep(2000);
      return;
    }
    window.location.reload();
  },
};
