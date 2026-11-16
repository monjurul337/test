import 'dart:convert';
import '../models/studio_models.dart';

enum StockMarketplace {
  adobeStock('Adobe Stock', 'https://contributor.stock.adobe.com/en/uploads'),
  shutterstock('Shutterstock', 'https://submit.shutterstock.com/'),
  pond5('Pond5', 'https://www.pond5.com/uploads'),
  magnific('Magnific', 'https://contributor.magnific.com/');

  final String label;
  final String uploadUrl;
  const StockMarketplace(this.label, this.uploadUrl);
}

class MultiMarketplaceService {
  /// Exact Magnific XHR API (/xhr/upload/session -> PUT -> /stored -> /update -> /submit)
  /// extracted from magnific-meta-writer-v1.2.3(1).zip
  static String buildMagnificApiUploadAndSubmitScript(
    AdobeMetadata meta,
    String base64Video,
    String fileName, {
    String base64Thumb = '',
    bool autoSubmit = true,
  }) {
    final title = jsonEncode(meta.title);
    final tags = jsonEncode(meta.keywords.take(49).toList());
    final b64Vid = jsonEncode(base64Video);
    final b64Thumb = jsonEncode(base64Thumb);
    final fn = jsonEncode(fileName);
    final isAi = meta.isAiGenerated ? 'true' : 'false';

    return '''
(async function() {
  try {
    const req = async (path, body) => {
      const r = await fetch(path, {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json', 'X-Requested-With': 'XMLHttpRequest' },
        body: JSON.stringify(body)
      });
      const j = await r.json().catch(() => ({}));
      if (!r.ok) throw new Error(path + ' HTTP ' + r.status);
      return j;
    };

    // Detect userId from page or fallback
    let userId = 'contributor';
    const uidMatch = document.documentElement.innerHTML.match(/"user_?id"\s*:\s*"?(\d+)"?/i);
    if (uidMatch) userId = uidMatch[1];

    const baseName = ($fn).replace(/\.[^.]+\$/, '') + '_' + Date.now();

    // 1. Optional thumbnail upload
    if ($b64Thumb) {
      const tBin = atob($b64Thumb);
      const tBytes = new Uint8Array(tBin.length);
      for (let i = 0; i < tBin.length; i++) tBytes[i] = tBin.charCodeAt(i);
      const jpgPath = userId + '/video/' + baseName + '.jpg';
      const s1 = await req('/xhr/upload/session', { path: jpgPath, content_type: 'image/jpeg' });
      await fetch(s1.data.session_url, { method: 'PUT', headers: { 'Content-Type': 'image/jpeg' }, body: new Blob([tBytes], { type: 'image/jpeg' }) });
      await req('/xhr/upload/stored', { path: jpgPath, asset_type: 'video' });
    }

    // 2. Video upload via signed session_url
    const vBin = atob($b64Vid);
    const vBytes = new Uint8Array(vBin.length);
    for (let i = 0; i < vBin.length; i++) vBytes[i] = vBin.charCodeAt(i);
    const mp4Path = userId + '/video/' + baseName + '.mp4';
    const s2 = await req('/xhr/upload/session', { path: mp4Path, content_type: 'video/mp4' });
    await fetch(s2.data.session_url, { method: 'PUT', headers: { 'Content-Type': 'video/mp4' }, body: new Blob([vBytes], { type: 'video/mp4' }) });
    const stored = await req('/xhr/upload/stored', { path: mp4Path, asset_type: 'video' });
    const assetId = stored && stored.data && stored.data.asset ? Number(stored.data.asset.id) : 0;
    if (!assetId) throw new Error('Magnific asset ID not returned');

    // 3. Update Title, Tags, and is_ai
    await req('/xhr/upload/update', { ids: [assetId], title: $title });
    await req('/xhr/upload/update', { ids: [assetId], tags: $tags });
    await req('/xhr/upload/update', { ids: [assetId], is_ai: $isAi });

    // 4. Submit to Review
    if ($autoSubmit) {
      await new Promise(r => setTimeout(r, 700 + Math.floor(Math.random() * 800)));
      await req('/xhr/upload/submit', { ids: [assetId] });
    }
    return JSON.stringify({ ok: true, market: 'Magnific', assetId });
  } catch (e) {
    return JSON.stringify({ ok: false, market: 'Magnific', error: String(e) });
  }
})();
''';
  }

  /// Exact Pond5 my_uploads_ajax API (changeName, changeDesc, changeKeywords)
  /// extracted from Pond5_Meta_Writer_v1.9.12(1).zip
  static String buildPond5ApiScript(
    AdobeMetadata meta,
    String base64Video,
    String fileName, {
    bool autoSubmit = true,
  }) {
    final title = jsonEncode(meta.title);
    final desc = jsonEncode('${meta.title}. Seamless high-resolution commercial motion background.');
    final tags = jsonEncode(meta.keywords.take(49).join(', '));
    final b64 = jsonEncode(base64Video);
    final fn = jsonEncode(fileName);

    return '''
(async function() {
  try {
    // 1. Attach file to Pond5 uploader if file input is present
    const fileInput = document.querySelector('input[type="file"]');
    if (fileInput) {
      const res = await fetch("data:video/mp4;base64," + $b64);
      const blob = await res.blob();
      const file = new File([blob], $fn, { type: "video/mp4" });
      const dt = new DataTransfer();
      dt.items.add(file);
      fileInput.files = dt.files;
      fileInput.dispatchEvent(new Event('change', { bubbles: true }));
    }

    // 2. Extract Pond5 CSRF token & latest itemId
    const tokInp = document.querySelector('input[name="token"], input[name="csrf_token"], input[name="csrfToken"]');
    const tokMeta = document.querySelector('meta[name="csrf-token"], meta[name="token"]');
    const token = (tokInp && tokInp.value) || (tokMeta && tokMeta.content) || window.token || window.csrfToken || '';

    const idMatch = document.documentElement.innerHTML.match(/itemid[=:]\s*["']?(\d{6,12})/i);
    const itemId = idMatch ? idMatch[1] : '';

    if (itemId) {
      const p5Ajax = async (what, params) => {
        const fd = new URLSearchParams();
        if (token) fd.set('token', token);
        for (const [k, v] of Object.entries(params)) fd.set(k, String(v));
        const r = await fetch('/index.php?page=my_uploads_ajax&what=' + encodeURIComponent(what) + '&itemid=' + encodeURIComponent(itemId), {
          method: 'POST',
          credentials: 'include',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8', 'X-Requested-With': 'XMLHttpRequest' },
          body: fd.toString()
        });
        return r.text();
      };

      await p5Ajax('changeName', { itemid: itemId, id: itemId, name: $title });
      await p5Ajax('changeDesc', { itemid: itemId, id: itemId, description: $desc, desc: $desc, value: $desc });
      await p5Ajax('changeKeywords', { itemid: itemId, id: itemId, keywords: $tags, value: $tags });
    }

    if (${autoSubmit ? 'true' : 'false'}) {
      await new Promise(r => setTimeout(r, 800));
      const subBtn = Array.from(document.querySelectorAll('button, input[type="submit"], a'))
        .find(b => /save and submit|submit for review|send to curation/i.test((b.innerText || '') + ' ' + (b.value || '')));
      if (subBtn) subBtn.click();
    }
    return JSON.stringify({ ok: true, market: 'Pond5', itemId });
  } catch (e) {
    return JSON.stringify({ ok: false, market: 'Pond5', error: String(e) });
  }
})();
''';
  }

  static String buildUploadAndFillScript(
    StockMarketplace market,
    AdobeMetadata meta,
    String base64Video,
    String fileName, {
    bool autoSubmit = false,
  }) {
    if (market == StockMarketplace.magnific) {
      return buildMagnificApiUploadAndSubmitScript(meta, base64Video, fileName, autoSubmit: autoSubmit);
    }
    if (market == StockMarketplace.pond5) {
      return buildPond5ApiScript(meta, base64Video, fileName, autoSubmit: autoSubmit);
    }
    // Shutterstock fallback DOM script until HAR is provided
    final title = jsonEncode(meta.title);
    final desc = jsonEncode('${meta.title}. Seamless high-resolution commercial motion background.');
    final tags = jsonEncode(meta.keywords.take(49).join(', '));
    final b64 = jsonEncode(base64Video);
    final fn = jsonEncode(fileName);
    return '''
(async function() {
  try {
    const res = await fetch("data:video/mp4;base64," + $b64);
    const blob = await res.blob();
    const file = new File([blob], $fn, { type: "video/mp4" });
    const dt = new DataTransfer();
    dt.items.add(file);
    const fileInput = document.querySelector('input[type="file"]');
    if (fileInput) {
      fileInput.files = dt.files;
      fileInput.dispatchEvent(new Event('change', { bubbles: true }));
    }
    await new Promise(r => setTimeout(r, 1200));
    const setVal = (el, val) => {
      if (!el) return;
      const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set
        || Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value')?.set;
      if (setter) setter.call(el, val);
      else el.value = val;
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
    };
    setVal(document.querySelector('input[name*="title"], textarea[name*="title"], input[placeholder*="Title"]'), $title);
    setVal(document.querySelector('textarea[name*="description"], textarea[placeholder*="Description"]'), $desc);
    setVal(document.querySelector('textarea[name*="keyword"], input[name*="keyword"], textarea[placeholder*="keyword"]'), $tags);
    if (${autoSubmit ? 'true' : 'false'}) {
      const btn = Array.from(document.querySelectorAll('button')).find(b => /submit|publish|save/i.test(b.innerText || '') && !b.disabled);
      if (btn) btn.click();
    }
    return JSON.stringify({ ok: true, market: 'Shutterstock' });
  } catch (e) {
    return JSON.stringify({ ok: false, market: 'Shutterstock', error: String(e) });
  }
})();
''';
  }
}
