import 'dart:convert';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../models/studio_models.dart';

class AdobeStockAutomation {
  static const String uploadUrl = 'https://contributor.stock.adobe.com/en/uploads';

  static const Map<String, int> categoryIds = {
    'Abstract': 10432,
    'Backgrounds': 10433,
    'Technology': 10443,
    'Science': 10441,
    'Graphic Resources': 10437,
    'Nature': 10439,
    'Business': 10434,
  };

  static Future<bool> hasActiveSession() async {
    final cookies = await CookieManager.instance().getCookies(
      url: WebUri('https://contributor.stock.adobe.com'),
    );
    return cookies.isNotEmpty;
  }

  /// Exact HAR-derived Save & Submit API calls from adobe-stock-meta-writer.zip:
  /// 1. Sniffs csrf-token from meta / cookie / window / HTML / XHR
  /// 2. POST /{locale}/indexation/save?m=1
  /// 3. POST /{locale}/content/submit?m=1
  static String buildHarApiSaveAndSubmitScript(
    AdobeMetadata meta, {
    required int assetId,
    required String contentUuid,
    bool autoSubmit = true,
  }) {
    final catId = categoryIds[meta.category] ?? 10432;
    final titleJson = jsonEncode(meta.title);
    final kwsJson = jsonEncode(meta.keywords.take(49).toList());
    final uuidJson = jsonEncode(contentUuid);

    return '''
(async function() {
  try {
    const findCsrf = () => {
      const m = document.querySelector('meta[name="csrf-token"], meta[name="_csrf"], meta[name="csrf_token"]');
      if (m && m.content) return m.content;
      const cm = document.cookie.match(/(?:^|;\s*)(csrf[_-]?token|CSRF-TOKEN|XSRF-TOKEN)=([^;]+)/i);
      if (cm) return decodeURIComponent(cm[2]);
      for (const k of ['csrfToken', 'CSRF_TOKEN', 'csrf_token', '__CSRF__', 'csrf']) {
        if (typeof window[k] === 'string' && window[k].length > 8) return window[k];
      }
      const hm = document.documentElement.innerHTML.match(/["'](?:csrf[_-]?token|csrfToken)["']\s*:\s*["']([A-Za-z0-9_-]{16,80})["']/i);
      return hm ? hm[1] : '';
    };

    const csrf = findCsrf();
    if (!csrf) return JSON.stringify({ ok: false, error: 'CSRF token not found on page.' });

    const seg = (location.pathname.split('/').filter(Boolean)[0] || 'en');
    const locale = /^[a-z]{2}(-[a-z]{2})?\$/i.test(seg) ? seg : 'en';
    const base = location.origin + '/' + locale;

    const headers = (acceptJson) => ({
      'Content-Type': 'application/json',
      'Accept': acceptJson ? 'application/json' : '*/*',
      'X-Requested-With': 'XMLHttpRequest',
      'X-Request-ID': (crypto.randomUUID ? crypto.randomUUID() : String(Date.now())),
      'csrf-token': csrf
    });

    // 1. Save Metadata: POST /{locale}/indexation/save?m=1
    const savePayload = [{
      category: $catId,
      contentType: 1,
      contentUuid: $uuidJson,
      id: $assetId,
      isIllustrative: false,
      isGenTech: ${meta.isAiGenerated ? 'true' : 'false'},
      isGenTechPropertyRelease: ${meta.isAiGenerated ? 'true' : 'false'},
      isIcon: false,
      iconType: null,
      premiumLevelId: 0,
      keywords: $kwsJson,
      language: 1,
      releases: [],
      hasReleases: false,
      status: 'state_data_complete',
      title: $titleJson,
      isIncludedInSubmission: null,
      customMetadataFields: [],
      countryId: 50
    }];

    const saveRes = await fetch(base + '/indexation/save?m=1', {
      method: 'POST',
      headers: headers(false),
      body: JSON.stringify(savePayload)
    });
    const saveJson = await saveRes.json();
    if (!saveRes.ok) return JSON.stringify({ ok: false, step: 'save', status: saveRes.status, data: saveJson });

    if (!${autoSubmit ? 'true' : 'false'}) {
      return JSON.stringify({ ok: true, saved: true, submitted: false, data: saveJson });
    }

    await new Promise(r => setTimeout(r, 700 + Math.floor(Math.random() * 900)));
    // 2. Submit for Review: POST /{locale}/content/submit?m=1
    const submitBody = {
      contentIdentifiers: [{ id: $assetId, uuid: $uuidJson, category: $catId, title: $titleJson }],
      isResubmitting: false,
      keywordsMap: { [String($assetId)]: $kwsJson }
    };
    const subRes = await fetch(base + '/content/submit?m=1', {
      method: 'POST',
      headers: headers(true),
      body: JSON.stringify(submitBody)
    });
    const subJson = await subRes.json();
    return JSON.stringify({ ok: subRes.ok, saved: true, submitted: true, data: subJson });
  } catch (e) {
    return JSON.stringify({ ok: false, error: String(e) });
  }
})();
''';
  }

  /// Fallback DOM filler + Submit when assetId/uuid are auto-read from current uploads grid
  static String buildFillAndSubmitScript(AdobeMetadata meta, {bool autoSubmit = true}) {
    final title = jsonEncode(meta.title);
    final tags = jsonEncode(meta.keywords.join(', '));
    final category = jsonEncode(meta.category);
    return '''
(async function() {
  try {
    const setVal = (el, val) => {
      if (!el) return false;
      const nativeSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set
        || Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value')?.set;
      if (nativeSetter) nativeSetter.call(el, val);
      else el.value = val;
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
      return true;
    };

    setVal(document.querySelector('input[name*="title"], textarea[name*="title"], input[placeholder*="Title"]'), $title);
    setVal(document.querySelector('textarea[name*="keyword"], input[name*="keyword"], textarea[placeholder*="keyword"]'), $tags);

    const catSelect = document.querySelector('select[name*="category"]');
    if (catSelect) {
      for (const opt of catSelect.options) {
        if (opt.text.toLowerCase().includes(($category).toLowerCase())) {
          catSelect.value = opt.value;
          catSelect.dispatchEvent(new Event('change', { bubbles: true }));
          break;
        }
      }
    }

    await new Promise(r => setTimeout(r, 500));
    if (${autoSubmit ? 'true' : 'false'}) {
      const submitBtn = Array.from(document.querySelectorAll('button'))
        .find(b => /submit/i.test(b.innerText || '') && !b.disabled);
      if (submitBtn) {
        submitBtn.click();
        return JSON.stringify({ ok: true, submitted: true });
      }
    }
    return JSON.stringify({ ok: true, submitted: false });
  } catch (e) {
    return JSON.stringify({ ok: false, error: String(e) });
  }
})();
''';
  }

  /// Zero-API full portfolio, sales & payout reader using logged-in Adobe Stock cookies
  static String buildFetchStatsScript() {
    return '''
(async function() {
  try {
    const fetchTxt = async (u) => {
      const r = await fetch(u, { credentials: 'include' });
      const html = await r.text();
      const doc = new DOMParser().parseFromString(html, 'text/html');
      return { doc, txt: doc.body ? doc.body.innerText : html };
    };

    const [ins, port, pay] = await Promise.all([
      fetchTxt('https://contributor.stock.adobe.com/en/insights').catch(() => ({ doc: null, txt: '' })),
      fetchTxt('https://contributor.stock.adobe.com/en/portfolio').catch(() => ({ doc: null, txt: '' })),
      fetchTxt('https://contributor.stock.adobe.com/en/payouts').catch(() => ({ doc: null, txt: '' })),
    ]);

    const numMatch = (txt, re) => {
      const m = txt.match(re);
      return m ? parseInt(m[1].replace(/,/g, ''), 10) : 0;
    };

    const allTxt = ins.txt + '\\n' + port.txt;
    const earnMatch = allTxt.match(/(\\$\\s?[0-9,]+(?:\\.\\d{2})?)/);

    // Extract payout rows
    const payouts = [];
    if (pay.doc) {
      const rows = pay.doc.querySelectorAll('table tr, [class*="payout"] [class*="row"]');
      for (const r of rows) {
        const t = (r.innerText || '').trim();
        const amt = t.match(/(\\$\\s?[0-9,]+\\.\\d{2})/);
        if (amt) {
          const dt = t.match(/([A-Za-z]{3,9}\\s+\\d{1,2},\\s+\\d{4}|\\d{4}-\\d{2}-\\d{2}|\\d{1,2}\\/\\d{1,2}\\/\\d{2,4})/);
          payouts.push({
            date: dt ? dt[1] : 'Payout',
            amount: amt[1].replace(/\\s+/g, ''),
            status: /pending/i.test(t) ? 'Pending' : 'Paid'
          });
        }
      }
    }

    // Calculate lifetime withdrawn sum
    let totalWithdrawnNum = 0;
    for (const p of payouts) {
      totalWithdrawnNum += parseFloat(p.amount.replace(/[^0-9.]/g, '')) || 0;
    }

    // Extract recent product sales from insights
    const recentSales = [];
    if (ins.doc) {
      const items = ins.doc.querySelectorAll('table tr, [class*="sale"], [class*="asset"]');
      for (const el of items) {
        const t = (el.innerText || '').trim();
        const amt = t.match(/(\\$\\s?[0-9,]+\\.\\d{2})/);
        if (amt && t.length > 8 && recentSales.length < 15) {
          const lines = t.split('\\n').map(x => x.trim()).filter(Boolean);
          recentSales.push({
            title: (lines[0] || 'Stock Asset').slice(0, 50),
            amount: amt[1].replace(/\\s+/g, ''),
            info: lines.slice(1, 3).join(' · ').slice(0, 40)
          });
        }
      }
    }

    return JSON.stringify({
      ok: true,
      inReview: numMatch(allTxt, /In\\s+review[\\s:]*([0-9,]+)/i),
      totalFiles: numMatch(allTxt, /(?:Online|Portfolio|Total\\s+files|Approved)[\\s:]*([0-9,]+)/i),
      downloads: numMatch(allTxt, /Downloads[\\s:]*([0-9,]+)/i),
      earnings: earnMatch ? earnMatch[1].replace(/\\s+/g, '') : '\$0.00',
      withdrawCount: payouts.length,
      totalWithdrawn: '\$' + totalWithdrawnNum.toFixed(2),
      payouts: payouts.slice(0, 20),
      recentSales: recentSales,
      chartPoints: recentSales.length
        ? recentSales.slice(0, 7).reverse().map(s => parseFloat(s.amount.replace(/[^0-9.]/g, '')) || 0)
        : [0, 0, 0, 0, 0, 0, 0]
    });
  } catch (e) {
    return JSON.stringify({ ok: false, error: String(e) });
  }
})();
''';
  }
}
