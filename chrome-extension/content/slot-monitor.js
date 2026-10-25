/**
 * Content Script: Slot Monitor
 * Continuously checks for available appointment dates.
 * Prioritizes user-selected preferred dates, then any available slot.
 */

const { sleep, click, log, showOverlay, waitForElement } = window.VisaBotUtils;

window.VisaBotSlotMonitor = {
  isRunning: false,
  lastCheck: null,
  foundSlot: null,

  /**
   * Parse available dates from the calendar/date-picker on the page.
   * Returns array of { dateStr, element } objects.
   */
  parseAvailableDates() {
    const available = [];

    // Strategy 1: Calendar cells that are enabled/available
    const calendarSelectors = [
      '.calendar td:not(.disabled):not(.unavailable):not(.past)',
      '[class*="calendar"] td.available',
      '[class*="datepicker"] td:not(.disabled)',
      '.fc-day:not(.fc-day-disabled)', // FullCalendar
      '[data-available="true"]',
      '[class*="day"]:not([class*="disabled"]):not([class*="unavailable"])',
    ];

    for (const sel of calendarSelectors) {
      const cells = document.querySelectorAll(sel);
      cells.forEach(cell => {
        if (cell.offsetParent !== null && !cell.classList.contains('disabled') && !cell.classList.contains('past')) {
          const dateAttr = cell.getAttribute('data-date') || cell.getAttribute('data-value') || cell.textContent.trim();
          if (dateAttr && dateAttr.length > 0) {
            available.push({ dateStr: dateAttr, element: cell });
          }
        }
      });
      if (available.length > 0) break;
    }

    // Strategy 2: Available date options in a select dropdown
    if (available.length === 0) {
      const dateSelect = document.querySelector('select[name*="date"], select[id*="date"], select[name*="appointment_date"]');
      if (dateSelect) {
        for (const option of dateSelect.options) {
          if (option.value && !option.disabled && option.value !== '' && option.value !== '0') {
            available.push({ dateStr: option.value, element: option });
          }
        }
      }
    }

    return available;
  },

  /**
   * Check if a date string matches any of the preferred dates.
   */
  matchesPreferredDate(dateStr, preferredDates) {
    if (!preferredDates || preferredDates.length === 0) return false;
    const normalized = dateStr.replace(/[^0-9\-\/]/g, '').trim();
    return preferredDates.some(pref => {
      const prefNorm = pref.replace(/[^0-9\-\/]/g, '').trim();
      return normalized.includes(prefNorm) || prefNorm.includes(normalized);
    });
  },

  /**
   * Select a date slot by clicking on its calendar cell or selecting from dropdown.
   */
  async selectSlot(slotObj) {
    const { dateStr, element } = slotObj;
    log(`Selecting slot: ${dateStr}`);
    showOverlay(`Slot found: <strong>${dateStr}</strong><br>Booking now...`, 'success');

    if (element.tagName === 'OPTION') {
      // It's a select dropdown option
      element.parentElement.value = element.value;
      element.parentElement.dispatchEvent(new Event('change', { bubbles: true }));
    } else {
      // Calendar cell click
      element.scrollIntoView({ behavior: 'smooth', block: 'center' });
      await sleep(300);
      element.click();
    }

    this.foundSlot = dateStr;
    await sleep(1000);

    // Click confirm/select time after date selection
    await this.selectTimeSlot();
  },

  /**
   * After date is selected, choose the first available time slot.
   */
  async selectTimeSlot() {
    await sleep(1000);

    const timeSelectors = [
      'select[name*="time"]', 'select[id*="time"]', 'select[name*="slot"]',
    ];

    for (const sel of timeSelectors) {
      const select = document.querySelector(sel);
      if (select && select.options.length > 1) {
        // Select first available non-empty time
        for (const opt of select.options) {
          if (opt.value && !opt.disabled && opt.value !== '0' && opt.value !== '') {
            select.value = opt.value;
            select.dispatchEvent(new Event('change', { bubbles: true }));
            log(`Time slot selected: ${opt.text}`);
            await sleep(500);
            break;
          }
        }
        break;
      }
    }

    // Click "Book" or "Select" button for time slots
    const timeSlotBtn = document.querySelector('[class*="time-slot"]:not(.unavailable), [class*="timeslot"]:not(.disabled)');
    if (timeSlotBtn) {
      timeSlotBtn.click();
      await sleep(500);
    }
  },

  /**
   * Main monitoring function - called by background alarm.
   * Returns true if a slot was found and booked.
   */
  async checkAndBook(config) {
    if (this.isRunning) {
      log('Slot check already running, skipping...', 'warn');
      return false;
    }

    this.isRunning = true;
    this.lastCheck = new Date();

    try {
      log(`Checking for slots... (${this.lastCheck.toLocaleTimeString()})`);

      // Detect if we're on the date selection page
      const calendarEl = document.querySelector('.calendar, [class*="calendar"], [class*="datepicker"]');
      const dateSelectEl = document.querySelector('select[name*="date"], select[id*="appointment"]');

      if (!calendarEl && !dateSelectEl) {
        log('Not on date selection page', 'warn');
        this.isRunning = false;
        return false;
      }

      const available = this.parseAvailableDates();

      if (available.length === 0) {
        log('No available slots found');
        showOverlay(`No slots available. Last checked: ${this.lastCheck.toLocaleTimeString()}`, 'warn');
        this.isRunning = false;

        // Try refreshing the calendar
        await this.refreshCalendar();
        return false;
      }

      log(`Found ${available.length} available slot(s)`);

      // Priority 1: Check for preferred dates
      const preferredDates = config.preferredDates || [];
      let targetSlot = null;

      for (const slot of available) {
        if (this.matchesPreferredDate(slot.dateStr, preferredDates)) {
          targetSlot = slot;
          log(`Preferred date found: ${slot.dateStr}`);
          break;
        }
      }

      // Priority 2: Take first available slot
      if (!targetSlot) {
        targetSlot = available[0];
        log(`Taking first available slot: ${targetSlot.dateStr}`);
      }

      await this.selectSlot(targetSlot);

      // Send notification
      chrome.runtime.sendMessage({
        type: 'slot_found',
        date: targetSlot.dateStr,
        config,
      });

      this.isRunning = false;
      return true;
    } catch (err) {
      log(`Slot check error: ${err.message}`, 'error');
      this.isRunning = false;
      return false;
    }
  },

  /**
   * Try to refresh the calendar to get updated availability.
   */
  async refreshCalendar() {
    // Click next month and back to trigger reload
    const nextBtn = document.querySelector('[class*="next"], [aria-label="Next month"], .calendar-next, .fc-next-button');
    const prevBtn = document.querySelector('[class*="prev"], [aria-label="Previous month"], .calendar-prev, .fc-prev-button');

    if (nextBtn && prevBtn) {
      nextBtn.click();
      await sleep(1000);
      prevBtn.click();
      await sleep(500);
      log('Calendar refreshed');
    }
  },
};

// Listen for slot check trigger from background SW
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.type === 'check_slots' && window.VisaBotSlotMonitor) {
    window.VisaBotSlotMonitor.checkAndBook(msg.config).then(found => {
      sendResponse({ found });
    });
    return true;
  }
});
