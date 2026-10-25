/**
 * Content Script: Form Filler
 * Auto-populates applicant profile data into the IVAC portal forms,
 * handles PDF file uploads, and mission/IVAC center selection.
 */

const { waitForElement, sleep, typeInto, selectOption, click, log, showOverlay } = window.VisaBotUtils;

window.VisaBotFormFiller = {
  /**
   * Fill applicant form fields from a profile object.
   */
  async fillApplicantForm(profile) {
    log('Filling applicant form...');
    showOverlay('Filling applicant form...', 'info');

    const fieldMap = [
      { keys: ['given_name', 'givenName', 'firstName', 'first_name'], selectors: ['input[name*="given"]', 'input[name*="first"]', '#given_name', '#firstName', 'input[placeholder*="Given Name"]'] },
      { keys: ['surname', 'lastName', 'last_name'], selectors: ['input[name*="surname"]', 'input[name*="last"]', '#surname', '#lastName', 'input[placeholder*="Surname"]'] },
      { keys: ['passport_no', 'passportNo', 'passport_number'], selectors: ['input[name*="passport"]', '#passport_no', '#passportNo', 'input[placeholder*="Passport"]'] },
      { keys: ['dob', 'date_of_birth', 'dateOfBirth'], selectors: ['input[name*="dob"]', 'input[name*="birth"]', '#dob', 'input[type="date"]'] },
      { keys: ['phone', 'mobile', 'phone_number'], selectors: ['input[name*="phone"]', 'input[name*="mobile"]', 'input[type="tel"]', '#phone', '#mobile'] },
      { keys: ['email'], selectors: ['input[name*="email"]', 'input[type="email"]', '#email'] },
      { keys: ['address'], selectors: ['input[name*="address"]', 'textarea[name*="address"]', '#address'] },
    ];

    for (const { keys, selectors } of fieldMap) {
      // Find which key exists in the profile
      let value = null;
      for (const key of keys) {
        if (profile[key]) { value = profile[key]; break; }
      }
      if (!value) continue;

      // Find which selector exists in the DOM
      for (const sel of selectors) {
        const el = document.querySelector(sel);
        if (el && el.offsetParent !== null) {
          typeInto(el, value);
          await sleep(200);
          log(`Filled ${sel}: ${value}`);
          break;
        }
      }
    }

    // Handle select dropdowns
    if (profile.nationality) {
      const natSelect = document.querySelector('select[name*="nationality"], select[id*="nationality"]');
      if (natSelect) { selectOption(natSelect, profile.nationality); await sleep(300); }
    }
    if (profile.gender) {
      const genSelect = document.querySelector('select[name*="gender"], select[id*="gender"]');
      if (genSelect) { selectOption(genSelect, profile.gender); await sleep(300); }
    }

    showOverlay('Applicant form filled!', 'success');
    log('Form fill complete.');
  },

  /**
   * Select mission (Indian high commission/consulate).
   */
  async selectMission(missionName) {
    log(`Selecting mission: ${missionName}`);
    showOverlay(`Selecting mission: ${missionName}...`, 'info');

    const selectors = [
      'select[name*="mission"]', 'select[id*="mission"]',
      'select[name*="high_commission"]', 'select[id*="highCommission"]',
    ];

    for (const sel of selectors) {
      const el = document.querySelector(sel);
      if (el) {
        const success = selectOption(el, missionName);
        if (success) {
          await sleep(500);
          log(`Mission selected: ${missionName}`);
          // Trigger change to load IVAC centers
          el.dispatchEvent(new Event('change', { bubbles: true }));
          return true;
        }
      }
    }

    // Try clicking mission cards/buttons
    const missionLinks = document.querySelectorAll('a, button, .mission-item, [class*="mission"]');
    for (const el of missionLinks) {
      if (el.textContent.toLowerCase().includes(missionName.toLowerCase())) {
        click(el);
        await sleep(800);
        log(`Mission selected via click: ${missionName}`);
        return true;
      }
    }

    log(`Mission not found: ${missionName}`, 'warn');
    return false;
  },

  /**
   * Select IVAC center.
   */
  async selectIvacCenter(centerName) {
    log(`Selecting IVAC center: ${centerName}`);

    // Wait for the IVAC center dropdown to be populated (it's usually dynamic)
    await sleep(1000);

    const selectors = [
      'select[name*="ivac"]', 'select[id*="ivac"]',
      'select[name*="center"]', 'select[id*="center"]',
      'select[name*="office"]', 'select[id*="office"]',
    ];

    for (const sel of selectors) {
      const el = document.querySelector(sel);
      if (el && el.options.length > 1) {
        const success = selectOption(el, centerName);
        if (success) {
          await sleep(500);
          el.dispatchEvent(new Event('change', { bubbles: true }));
          log(`IVAC center selected: ${centerName}`);
          return true;
        }
      }
    }

    log(`IVAC center not found: ${centerName}`, 'warn');
    return false;
  },

  /**
   * Select visa type and category.
   */
  async selectVisaDetails(visaType, visaCategory) {
    log(`Selecting visa: ${visaType} / ${visaCategory}`);

    const typeSelect = document.querySelector('select[name*="visa_type"], select[id*="visaType"], select[name*="type"]');
    if (typeSelect) {
      selectOption(typeSelect, visaType);
      await sleep(500);
    }

    const catSelect = document.querySelector('select[name*="category"], select[id*="category"]');
    if (catSelect) {
      selectOption(catSelect, visaCategory);
      await sleep(500);
    }
  },

  /**
   * Upload a PDF file to the file input.
   * @param {File} file - The File object to upload.
   */
  async uploadPDF(file) {
    log(`Uploading PDF: ${file.name}`);
    showOverlay(`Uploading PDF: ${file.name}...`, 'info');

    const fileInputSelectors = [
      'input[type="file"][accept*="pdf"]',
      'input[type="file"][name*="passport"]',
      'input[type="file"][name*="photo"]',
      'input[type="file"][name*="document"]',
      'input[type="file"]',
    ];

    for (const sel of fileInputSelectors) {
      const input = document.querySelector(sel);
      if (input && input.offsetParent !== null) {
        // Use DataTransfer to programmatically set the file
        const dt = new DataTransfer();
        dt.items.add(file);
        input.files = dt.files;
        input.dispatchEvent(new Event('change', { bubbles: true }));
        input.dispatchEvent(new Event('input', { bubbles: true }));
        await sleep(1000);
        log(`PDF uploaded to: ${sel}`);
        showOverlay(`PDF "${file.name}" uploaded!`, 'success');
        return true;
      }
    }

    log('File input not found', 'error');
    return false;
  },

  /**
   * Upload multiple PDFs (passport copy, photo, etc.) from profile.
   */
  async uploadProfileDocuments(profile) {
    if (!profile.documents || profile.documents.length === 0) return;

    const inputs = document.querySelectorAll('input[type="file"]');
    let inputIndex = 0;

    for (const doc of profile.documents) {
      if (inputIndex >= inputs.length) break;
      const input = inputs[inputIndex];
      if (!input.offsetParent) { inputIndex++; continue; }

      try {
        const resp = await fetch(doc.dataUrl);
        const blob = await resp.blob();
        const file = new File([blob], doc.name || 'document.pdf', { type: blob.type || 'application/pdf' });
        const dt = new DataTransfer();
        dt.items.add(file);
        input.files = dt.files;
        input.dispatchEvent(new Event('change', { bubbles: true }));
        await sleep(800);
        log(`Uploaded document: ${doc.name}`);
        inputIndex++;
      } catch (err) {
        log(`Failed to upload ${doc.name}: ${err.message}`, 'error');
      }
    }
  },

  /**
   * Click the form's next/proceed/submit button.
   */
  async clickNext() {
    const nextTexts = ['next', 'proceed', 'continue', 'submit', 'save & next'];
    for (const text of nextTexts) {
      const btn = window.VisaBotUtils.findButtonByText(text);
      if (btn && btn.offsetParent !== null && !btn.disabled) {
        click(btn);
        log(`Clicked "${text}" button`);
        await sleep(1500);
        return true;
      }
    }
    log('Next button not found', 'warn');
    return false;
  },
};
