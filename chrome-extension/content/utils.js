/**
 * Content Script: Utility helpers shared across all content scripts
 */

window.VisaBotUtils = {
  /**
   * Wait for an element matching the selector to appear in the DOM.
   */
  waitForElement(selector, timeout = 15000) {
    return new Promise((resolve, reject) => {
      const el = document.querySelector(selector);
      if (el) return resolve(el);

      const observer = new MutationObserver(() => {
        const found = document.querySelector(selector);
        if (found) {
          observer.disconnect();
          resolve(found);
        }
      });
      observer.observe(document.body, { childList: true, subtree: true });

      setTimeout(() => {
        observer.disconnect();
        reject(new Error(`Timeout waiting for: ${selector}`));
      }, timeout);
    });
  },

  /**
   * Wait for any element matching an array of selectors.
   */
  waitForAny(selectors, timeout = 15000) {
    return new Promise((resolve, reject) => {
      for (const sel of selectors) {
        const el = document.querySelector(sel);
        if (el) return resolve({ el, selector: sel });
      }
      const observer = new MutationObserver(() => {
        for (const sel of selectors) {
          const el = document.querySelector(sel);
          if (el) {
            observer.disconnect();
            return resolve({ el, selector: sel });
          }
        }
      });
      observer.observe(document.body, { childList: true, subtree: true });
      setTimeout(() => {
        observer.disconnect();
        reject(new Error(`Timeout waiting for any of: ${selectors.join(', ')}`));
      }, timeout);
    });
  },

  /**
   * Sleep for a given number of milliseconds.
   */
  sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  },

  /**
   * Type into an input field, dispatching events for React/Angular compatibility.
   */
  typeInto(el, value) {
    el.focus();
    el.value = '';
    const nativeInputValueSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
    if (nativeInputValueSetter) {
      nativeInputValueSetter.call(el, value);
    } else {
      el.value = value;
    }
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    el.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true }));
  },

  /**
   * Select an option in a <select> element by visible text or value.
   */
  selectOption(selectEl, optionTextOrValue) {
    for (const option of selectEl.options) {
      if (
        option.text.toLowerCase().includes(optionTextOrValue.toLowerCase()) ||
        option.value.toLowerCase().includes(optionTextOrValue.toLowerCase())
      ) {
        selectEl.value = option.value;
        selectEl.dispatchEvent(new Event('change', { bubbles: true }));
        return true;
      }
    }
    return false;
  },

  /**
   * Click an element safely.
   */
  click(el) {
    if (!el) return false;
    el.scrollIntoView({ behavior: 'smooth', block: 'center' });
    el.click();
    return true;
  },

  /**
   * Find a button by text content (case-insensitive).
   */
  findButtonByText(text) {
    const buttons = document.querySelectorAll('button, input[type="submit"], a.btn');
    for (const btn of buttons) {
      if (btn.textContent.trim().toLowerCase().includes(text.toLowerCase())) return btn;
    }
    return null;
  },

  /**
   * Log a message to the bot overlay and console.
   */
  log(msg, level = 'info') {
    const prefix = '[VisaBot]';
    const styles = { info: 'color:#4ade80', warn: 'color:#fb923c', error: 'color:#f87171' };
    console.log(`%c${prefix} ${msg}`, styles[level] || styles.info);
    window.dispatchEvent(new CustomEvent('visabot_log', { detail: { msg, level, ts: Date.now() } }));
  },

  /**
   * Get current page state by examining URL and DOM.
   */
  getPageState() {
    const url = window.location.href;
    const body = document.body.innerText.toLowerCase();

    if (url.includes('/appointment')) return 'appointment';
    if (url.includes('/mission')) return 'mission_select';
    if (body.includes('otp') || document.querySelector('input[name*="otp"], input[id*="otp"]')) return 'otp_input';
    if (document.querySelector('input[type="file"]')) return 'pdf_upload';
    if (document.querySelector('.calendar, .datepicker, [class*="calendar"]')) return 'date_select';
    if (body.includes('confirm') && body.includes('appointment')) return 'confirm';
    if (body.includes('success') || body.includes('booking confirmed')) return 'success';
    return 'unknown';
  },

  /**
   * Show a floating status overlay on the page.
   */
  showOverlay(message, type = 'info') {
    let overlay = document.getElementById('visabot-overlay');
    if (!overlay) {
      overlay = document.createElement('div');
      overlay.id = 'visabot-overlay';
      overlay.style.cssText = `
        position: fixed; bottom: 20px; right: 20px; z-index: 999999;
        background: rgba(10,10,20,0.95); border: 1px solid #4ade80;
        border-radius: 12px; padding: 14px 18px; color: #fff;
        font-family: 'Courier New', monospace; font-size: 13px;
        min-width: 280px; max-width: 380px;
        box-shadow: 0 4px 30px rgba(74,222,128,0.25);
        transition: all 0.3s ease;
      `;
      document.body.appendChild(overlay);
    }
    const colors = { info: '#4ade80', warn: '#fb923c', error: '#f87171', success: '#818cf8' };
    overlay.style.borderColor = colors[type] || colors.info;
    overlay.innerHTML = `
      <div style="display:flex;align-items:center;gap:10px;">
        <span style="font-size:18px;">${type === 'success' ? '✅' : type === 'error' ? '❌' : type === 'warn' ? '⚠️' : '🤖'}</span>
        <div>
          <div style="font-weight:700;color:${colors[type]};margin-bottom:3px;">IVAC Visa Bot</div>
          <div style="opacity:0.9;">${message}</div>
        </div>
      </div>
    `;
  },
};
