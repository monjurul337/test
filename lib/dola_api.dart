import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import 'cloudinary_api.dart' show GenerationResult, GenerationTiming;

import 'secure_store.dart';

/// Exception thrown when a Dola AI request fails.
class DolaApiException implements Exception {
  final String message;
  final String code;

  const DolaApiException(this.message, {this.code = 'DOLA_ERROR'});

  @override
  String toString() => message;
}

/// Normalized Dola (dola.com) session cookies.
class DolaSession {
  final String sessionId;
  final String odinTt;
  final String sidGuard;
  final String storeIdc;
  final String carrierRegion;
  final String uid;
  final String ttwid;
  final Map<String, String> rawCookies;
  final String rawText;

  const DolaSession({
    required this.sessionId,
    this.odinTt = '',
    this.sidGuard = '',
    this.storeIdc = 'mya',
    this.carrierRegion = 'us',
    this.uid = '',
    this.ttwid = '',
    this.rawCookies = const {},
    this.rawText = '',
  });

  bool get isValid => sessionId.trim().isNotEmpty;

  String get summary {
    if (!isValid) return 'No valid session (missing sessionid cookie)';
    final uidStr = uid.isEmpty ? 'guest' : uid;
    return 'Dola Session Active · UID: $uidStr · Region: $carrierRegion · IDC: $storeIdc';
  }

  /// Cookie header formatted for ByteDance/Dola API requests.
  String get cookieHeader {
    if (rawCookies.isNotEmpty) {
      final map = Map<String, String>.from(rawCookies);
      if (sessionId.isNotEmpty) {
        map['sessionid'] = sessionId;
        map['sessionid_ss'] = sessionId;
        map['sid_tt'] = sessionId;
      }
      return map.entries.map((e) => '${e.key}=${e.value}').join('; ');
    }
    final parts = <String>[];
    if (storeIdc.isNotEmpty) parts.add('store-idc=$storeIdc');
    if (carrierRegion.isNotEmpty) parts.add('store-country-code=$carrierRegion');
    parts.add('sessionid=$sessionId');
    parts.add('sessionid_ss=$sessionId');
    parts.add('sid_tt=$sessionId');
    if (odinTt.isNotEmpty) parts.add('odin_tt=$odinTt');
    if (sidGuard.isNotEmpty) parts.add('sid_guard=$sidGuard');
    if (ttwid.isNotEmpty) parts.add('ttwid=$ttwid');
    return parts.join('; ');
  }

  /// Parses cookie data from:
  /// 1) Cookie-Editor or Playwright JSON export
  /// 2) Header string (`sessionid=...; odin_tt=...`)
  /// 3) Netscape HTTP cookie file format
  static DolaSession fromString(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return const DolaSession(sessionId: '');

    final cookies = <String, String>{};

    // 1. JSON Array or Map
    if (text.startsWith('[') || text.startsWith('{')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final n = (item['name'] ?? '').toString().trim();
              final v = (item['value'] ?? '').toString().trim();
              if (n.isNotEmpty) cookies[n] = v;
            }
          }
        } else if (decoded is Map) {
          if (decoded['cookies'] is List) {
            for (final item in decoded['cookies']) {
              if (item is Map) {
                final n = (item['name'] ?? '').toString().trim();
                final v = (item['value'] ?? '').toString().trim();
                if (n.isNotEmpty) cookies[n] = v;
              }
            }
          } else {
            decoded.forEach((k, v) {
              final n = k.toString().trim();
              final val = v.toString().trim();
              if (n.isNotEmpty) cookies[n] = val;
            });
          }
        }
      } catch (_) {}
    }

    // 2. Netscape format or Header String
    if (cookies.isEmpty) {
      final lines = text.split('\n');
      for (var line in lines) {
        line = line.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        if (line.contains('\t')) {
          final parts = line.split('\t');
          if (parts.length >= 7) {
            final n = parts[5].trim();
            final v = parts[6].trim();
            if (n.isNotEmpty) cookies[n] = v;
          }
        } else if (line.contains(';')) {
          for (final part in line.split(';')) {
            final idx = part.indexOf('=');
            if (idx > 0) {
              final n = part.substring(0, idx).trim();
              final v = part.substring(idx + 1).trim();
              if (n.isNotEmpty) cookies[n] = v;
            }
          }
        } else if (line.contains('=')) {
          final idx = line.indexOf('=');
          if (idx > 0) {
            final n = line.substring(0, idx).trim();
            final v = line.substring(idx + 1).trim();
            if (n.isNotEmpty) cookies[n] = v;
          }
        }
      }
    }

    final sid = cookies['sessionid'] ?? cookies['sessionid_ss'] ?? '';
    final odin = cookies['odin_tt'] ?? '';
    final sidGuard = cookies['sid_guard'] ?? '';
    final storeIdc = cookies['store-idc'] ?? 'mya';
    final carrier = (cookies['store-country-code'] ?? 'us').toLowerCase();
    final uid = cookies['uid_tt'] ?? cookies['uid_tt_ss'] ?? cookies['uid'] ?? '';
    final ttwid = cookies['ttwid'] ?? '';

    return DolaSession(
      sessionId: sid,
      odinTt: odin,
      sidGuard: sidGuard,
      storeIdc: storeIdc,
      carrierRegion: carrier,
      uid: uid,
      ttwid: ttwid,
      rawCookies: cookies,
      rawText: raw,
    );
  }

  /// Parses bulk cookie text (from a .txt file, pasted accounts, or JSON list)
  /// into a list of valid DolaSession accounts.
  static List<DolaSession> parseBulk(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return [];

    final result = <DolaSession>[];

    // 1. JSON Array
    if (text.startsWith('[') || text.startsWith('{')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is List) {
          // List of cookie lists: [[{name: ...}], [{name: ...}]]
          if (decoded.isNotEmpty && decoded.first is List) {
            for (final sub in decoded) {
              final s = DolaSession.fromString(jsonEncode(sub));
              if (s.isValid) result.add(s);
            }
          } else if (decoded.isNotEmpty && decoded.first is Map) {
            // Check if multiple sessionids are in one flat list
            final sids = <int>[];
            for (var i = 0; i < decoded.length; i++) {
              final n = (decoded[i]['name'] ?? '').toString().toLowerCase();
              if (n == 'sessionid' || n == 'sessionid_ss') {
                sids.add(i);
              }
            }
            if (sids.length > 1) {
              for (var i = 0; i < sids.length; i++) {
                final start = sids[i];
                final end = (i + 1 < sids.length) ? sids[i + 1] : decoded.length;
                final slice = decoded.sublist(start, end);
                final s = DolaSession.fromString(jsonEncode(slice));
                if (s.isValid) result.add(s);
              }
            } else {
              final s = DolaSession.fromString(text);
              if (s.isValid) result.add(s);
            }
          }
        } else if (decoded is Map) {
          final s = DolaSession.fromString(text);
          if (s.isValid) result.add(s);
        }
      } catch (_) {}
    }

    if (result.isNotEmpty) return _dedupSessions(result);

    // 2. Line-by-line / text blocks
    final lines = text.split('\n');
    final currentBlock = <String>[];

    void flush() {
      if (currentBlock.isEmpty) return;
      final blockText = currentBlock.join('\n').trim();
      currentBlock.clear();
      if (blockText.isEmpty) return;
      final s = DolaSession.fromString(blockText);
      if (s.isValid) result.add(s);
    }

    for (var line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        flush();
        continue;
      }
      if (trimmed.startsWith('---') ||
          trimmed.startsWith('===') ||
          trimmed.startsWith('***')) {
        flush();
        continue;
      }
      // If line is a complete header string containing sessionid and we already have one
      if (trimmed.contains('sessionid=') &&
          !trimmed.startsWith('#') &&
          currentBlock.any((l) => l.contains('sessionid='))) {
        flush();
      }
      currentBlock.add(line);
    }
    flush();

    // Fallback if nothing matched
    if (result.isEmpty) {
      final s = DolaSession.fromString(text);
      if (s.isValid) result.add(s);
    }

    return _dedupSessions(result);
  }

  static List<DolaSession> _dedupSessions(List<DolaSession> list) {
    final seen = <String>{};
    final out = <DolaSession>[];
    for (final s in list) {
      if (s.isValid && !seen.contains(s.sessionId)) {
        seen.add(s.sessionId);
        out.add(s);
      }
    }
    return out;
  }
}

/// Pure Dart implementation of the ByteDance request signature (X-Gorgon, X-Khronos, X-Ladon).
class DolaSigner {
  DolaSigner._();

  static const int defaultKeyLen = 0;
  static const int defaultHeapPtr = 0;
  static const String sessionFixed =
      '7OdAQJLu50UcXnEAwvWduFxCCYujlcj1U5wViru05cv8wZXd';
  static const List<int> flags = [0x00, 0x05, 0x09, 0x04];

  static Uint8List _b9f3a(int keyLen, int heapPtr) {
    return Uint8List.fromList([
      0x4a,
      keyLen & 0xff,
      0x16,
      (heapPtr >> 8) & 0xff,
      0x47,
      0x6c,
      (keyLen >> 8) & 0xff,
      heapPtr & 0xff,
    ]);
  }

  static List<int> _rc4Init(List<int> key) {
    final s = List<int>.generate(256, (i) => i);
    var j = 0;
    final keyLen = key.length;
    for (var i = 0; i < 256; i++) {
      j = (j + s[i] + key[i % keyLen]) & 0xff;
      final temp = s[i];
      s[i] = s[j];
      s[j] = temp;
    }
    return s;
  }

  static Uint8List _rc4Crypt(List<int> sBox, List<int> data) {
    final s = List<int>.from(sBox);
    final result = Uint8List(data.length);
    var i = 0;
    var j = 0;
    for (var idx = 0; idx < data.length; idx++) {
      i = (i + 1) & 0xff;
      j = (j + s[i]) & 0xff;
      final temp = s[i];
      s[i] = s[j];
      s[j] = temp;
      final k = s[(s[i] + s[j]) & 0xff];
      result[idx] = data[idx] ^ k;
    }
    return result;
  }

  static int _reverseBits(int b) {
    var r = 0;
    for (var i = 0; i < 8; i++) {
      r = (r << 1) | ((b >> i) & 1);
    }
    return r;
  }

  static Uint8List _transform(Uint8List buf) {
    final n = buf.length;
    final result = Uint8List(n);
    for (var i = 0; i < n; i++) {
      final ns = ((buf[i] & 0x0f) << 4) | ((buf[i] >> 4) & 0x0f);
      int val;
      if (i + 1 < n) {
        val = (ns ^ buf[i + 1]) & 0xff;
      } else if (n > 1) {
        val = (ns ^ result[0]) & 0xff;
      } else {
        val = ns;
      }
      final rbit = _reverseBits(val);
      result[i] = (n ^ (~rbit & 0xff)) & 0xff;
    }
    return result;
  }

  static Uint8List _encryptBlock(Uint8List plain20, int keyLen, int heapPtr) {
    assert(plain20.length == 20);
    final key8 = _b9f3a(keyLen, heapPtr);
    final s = _rc4Init(key8);
    final enc = _rc4Crypt(s, plain20);
    final trans = _transform(enc);
    final header = Uint8List.fromList([
      0x84,
      0x04,
      heapPtr & 0xff,
      (heapPtr >> 8) & 0xff,
      keyLen & 0xff,
      (keyLen >> 8) & 0xff,
    ]);
    final out = Uint8List(header.length + trans.length);
    out.setRange(0, header.length, header);
    out.setRange(header.length, out.length, trans);
    return out;
  }

  static Uint8List _buildPlain(String signingString, int timestamp) {
    final md5Hash = md5.convert(utf8.encode(signingString)).bytes.sublist(0, 4);
    final b = ByteData(4)..setUint32(0, timestamp & 0xffffffff, Endian.big);
    final tsBytes = b.buffer.asUint8List();
    final plain = Uint8List(20);
    plain.setRange(0, 4, md5Hash);
    plain.setRange(4, 8, const [0, 0, 0, 0]);
    plain.setRange(8, 12, const [0, 0, 0, 0]);
    plain.setRange(12, 16, flags);
    plain.setRange(16, 20, tsBytes);
    return plain;
  }

  static Map<String, String> sign(String url, {int? timestamp}) {
    final ts = timestamp ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
    final signingString = url.contains('?') ? url.split('?')[1] : '';
    final plain = _buildPlain(signingString, ts);
    final block = _encryptBlock(plain, defaultKeyLen, defaultHeapPtr);
    final hexStr = block.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return {
      'X-Gorgon': hexStr,
      'X-Khronos': ts.toString(),
      'X-Ladon': sessionFixed,
    };
  }
}

/// Manages a pool of multiple Dola AI sessions for load balancing,
/// automatic rotation, and failover across accounts.
class DolaPool {
  static final DolaPool instance = DolaPool._();
  DolaPool._();

  List<DolaSession> _sessions = [];
  int _currentIndex = 0;
  bool autoRotate = true;

  List<DolaSession> get sessions => List.unmodifiable(_sessions);
  int get count => _sessions.length;
  bool get isEmpty => _sessions.isEmpty;
  bool get isNotEmpty => _sessions.isNotEmpty;
  int get currentIndex => _currentIndex;

  void setSessions(List<DolaSession> list) {
    _sessions = list.where((s) => s.isValid).toList();
    if (_currentIndex >= _sessions.length) _currentIndex = 0;
  }

  void addSession(DolaSession session) {
    if (session.isValid &&
        !_sessions.any((s) => s.sessionId == session.sessionId)) {
      _sessions.add(session);
    }
  }

  void addSessions(List<DolaSession> list) {
    for (final s in list) {
      addSession(s);
    }
  }

  void removeAt(int index) {
    if (index >= 0 && index < _sessions.length) {
      _sessions.removeAt(index);
      if (_currentIndex >= _sessions.length) _currentIndex = 0;
    }
  }

  void clear() {
    _sessions.clear();
    _currentIndex = 0;
  }

  DolaSession? nextSession() {
    if (_sessions.isEmpty) return null;
    final s = _sessions[_currentIndex % _sessions.length];
    if (autoRotate && _sessions.length > 1) {
      _currentIndex = (_currentIndex + 1) % _sessions.length;
    }
    return s;
  }

  DolaSession? get currentSession {
    if (_sessions.isEmpty) return null;
    return _sessions[_currentIndex % _sessions.length];
  }

  Future<void> loadFromStore() async {
    final rawList = await DolaStore.loadBulk();
    final loaded = <DolaSession>[];
    for (final raw in rawList) {
      final parsed = DolaSession.parseBulk(raw);
      loaded.addAll(parsed);
    }
    setSessions(loaded);
    autoRotate = await AppPrefs.dolaAutoRotate();
  }

  Future<void> saveToStore() async {
    final rawList = _sessions
        .map((s) => s.rawText.isNotEmpty ? s.rawText : s.cookieHeader)
        .toList();
    await DolaStore.saveBulk(rawList);
    await AppPrefs.setDolaAutoRotate(autoRotate);
  }

  Future<Map<int, String>> testAll({
    void Function(int index, int total, String status)? onProgress,
  }) async {
    final results = <int, String>{};
    for (var i = 0; i < _sessions.length; i++) {
      final s = _sessions[i];
      onProgress?.call(i + 1, _sessions.length, 'Testing account ${i + 1}...');
      try {
        final api = DolaApi(s);
        final ok = await api.testConnection();
        results[i] = ok ? 'Active' : 'Failed';
      } catch (e) {
        results[i] = '$e';
      }
    }
    return results;
  }
}

/// Dola AI Image Generation client using https://www.dola.com session cookies.
class DolaApi {
  final DolaSession session;

  DolaApi(this.session);

  static const String _webUrl = 'https://www.dola.com/chat/completion';
  static const String _appUrl =
      'https://api16-normal-i18n-myb.dola.com/chat/completion';
  static const String _botId = '7339470689562525703'; // Dola web bot

  /// Tests if the Dola session is active.
  Future<bool> testConnection() async {
    if (!session.isValid) {
      throw const DolaApiException('Session cookies missing (sessionid not found).');
    }
    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final payload = _buildPayload(
        text: 'hello',
        conversationId: '',
        lastMessageIndex: 0,
        lastSectionId: '',
        localConvId: 'ais_test_$nowMs',
      );
      final bodyBytes = utf8.encode(jsonEncode(payload));

      // 1. Try web endpoint first
      http.Response? res;
      try {
        res = await http
            .post(Uri.parse(_webUrl),
                headers: _buildWebHeaders(), body: bodyBytes)
            .timeout(const Duration(seconds: 15));
      } catch (_) {}

      // 2. If web endpoint didn't connect, try app endpoint with signature
      if (res == null || res.statusCode != 200) {
        final queryParams = _buildQueryParams(nowMs);
        final url = '$_appUrl?$queryParams&_rticket=$nowMs';
        final sig = DolaSigner.sign(url, timestamp: nowMs ~/ 1000);
        final headers = _buildAppHeaders(nowMs, sig);
        res = await http
            .post(Uri.parse(url), headers: headers, body: bodyBytes)
            .timeout(const Duration(seconds: 15));
      }

      final agwLogin = res.headers['x-tt-agw-login'];
      final body = res.body;

      if (agwLogin == '0' ||
          body.contains('"error_msg":"login invalid"') ||
          body.contains('"error_code":710012001')) {
        throw const DolaApiException(
            'Dola rejected cookies: login invalid. Please log in to https://www.dola.com in your browser and export fresh cookies.');
      }

      if (body.contains('STREAM_ERROR')) {
        final errorMatch = RegExp(r'"error_msg"\s*:\s*"([^"]+)"').firstMatch(body);
        final msg = errorMatch?.group(1) ?? 'Session error';
        throw DolaApiException('Dola returned error: $msg');
      }

      if (res.statusCode == 200) {
        return true;
      }
      throw DolaApiException('HTTP ${res.statusCode}: $body');
    } catch (e) {
      if (e is DolaApiException) rethrow;
      throw DolaApiException('Connection test failed: $e');
    }
  }

  /// Generates an image using Dola AI text-to-image.
  Future<GenerationResult> textToImage({
    required String prompt,
    String? modelId,
    String? aspectRatio,
    String? resolution,
    String? format,
    int? seed,
    void Function(String status)? onStatus,
    void Function(String status, Duration elapsed)? onProgress,
  }) async {
    if (!session.isValid) {
      throw const DolaApiException(
          'Dola session cookies not configured. Please paste your dola.com cookies in Settings.');
    }

    final startTime = DateTime.now();
    onStatus?.call('Sending prompt to Dola AI...');
    onProgress?.call('pending', Duration.zero);

    // Formulate a high-directive prompt for Dola's generation engine
    var fullPrompt = prompt.trim();
    final lower = fullPrompt.toLowerCase();
    final needsPrefix = !lower.startsWith('draw') &&
        !lower.startsWith('generate') &&
        !lower.startsWith('create') &&
        !lower.startsWith('paint') &&
        !lower.contains('image of');

    if (needsPrefix) {
      fullPrompt = 'Draw an image: $fullPrompt';
    }

    if (aspectRatio != null && aspectRatio.isNotEmpty && !lower.contains('aspect ratio')) {
      fullPrompt += ' (aspect ratio: $aspectRatio)';
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final payload = _buildPayload(
      text: fullPrompt,
      conversationId: '',
      lastMessageIndex: 0,
      lastSectionId: '',
      localConvId: 'ais_$nowMs',
    );

    final submitEnd = DateTime.now();
    final submitDuration = submitEnd.difference(startTime);

    onStatus?.call('Waiting for Dola AI model generation...');

    final client = http.Client();
    try {
      // Create request: try web endpoint
      http.Request request = http.Request('POST', Uri.parse(_webUrl));
      request.headers.addAll(_buildWebHeaders());
      request.body = jsonEncode(payload);

      http.StreamedResponse streamedResponse;
      try {
        streamedResponse = await client.send(request).timeout(
              const Duration(seconds: 120),
              onTimeout: () => throw const DolaApiException('Dola AI request timed out.'),
            );
      } catch (e) {
        // Fallback to app endpoint with signature if web endpoint failed to connect
        final queryParams = _buildQueryParams(nowMs);
        final url = '$_appUrl?$queryParams&_rticket=$nowMs';
        final sig = DolaSigner.sign(url, timestamp: nowMs ~/ 1000);
        request = http.Request('POST', Uri.parse(url));
        request.headers.addAll(_buildAppHeaders(nowMs, sig));
        request.body = jsonEncode(payload);
        streamedResponse = await client.send(request).timeout(
              const Duration(seconds: 120),
              onTimeout: () => throw const DolaApiException('Dola AI request timed out.'),
            );
      }

      if (streamedResponse.statusCode != 200) {
        final body = await streamedResponse.stream.bytesToString();
        throw DolaApiException('Dola API HTTP ${streamedResponse.statusCode}: $body');
      }

      String? foundImageUrl;
      final textBuffer = StringBuffer();
      DateTime? renderStart;

      final timer = Timer.periodic(const Duration(milliseconds: 500), (t) {
        final elapsed = DateTime.now().difference(startTime);
        onProgress?.call(foundImageUrl != null ? 'done' : 'rendering', elapsed);
      });

      try {
        final lines = streamedResponse.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter());

        String? currentEvent;
        await for (final line in lines) {
          if (line.startsWith('event:')) {
            currentEvent = line.substring(6).trim();
          } else if (line.startsWith('data:')) {
            renderStart ??= DateTime.now();
            final dataStr = line.substring(5).trim();
            if (dataStr.isNotEmpty && dataStr != '{}') {
              try {
                final json = jsonDecode(dataStr);

                // Check for server error events
                if (currentEvent == 'STREAM_ERROR') {
                  final msg = json['error_msg']?.toString() ?? 'Stream error';
                  final code = json['error_code']?.toString() ?? '';
                  if (msg.contains('login invalid') || code == '710012001') {
                    throw const DolaApiException(
                        'Dola rejected session: login invalid. Please log in to https://www.dola.com in your browser and export fresh cookies.');
                  }
                  throw DolaApiException('Dola error ($code): $msg');
                }

                final img = _extractImageUrlFromJson(currentEvent, json);
                if (img != null && img.isNotEmpty) {
                  foundImageUrl = img;
                  break;
                }
                final txt = _extractTextFromJson(currentEvent, json);
                if (txt != null) {
                  textBuffer.write(txt);
                  final matched = _findImageUrlInText(txt);
                  if (matched != null) {
                    foundImageUrl = matched;
                    break;
                  }
                }
              } catch (e) {
                if (e is DolaApiException) rethrow;
              }
            }
          }
        }
      } finally {
        timer.cancel();
      }

      // Check accumulated text if URL not found in stream chunks
      foundImageUrl ??= _findImageUrlInText(textBuffer.toString());

      if (foundImageUrl == null || foundImageUrl.isEmpty) {
        final reply = textBuffer.toString().trim();
        if (reply.isNotEmpty) {
          throw DolaApiException('Dola replied: "$reply"');
        }
        throw const DolaApiException(
            'No image returned by Dola AI. Check your cookies or try a different prompt.');
      }

      onStatus?.call('Image generated! Downloading preview...');

      // Retrieve image size and dimensions
      int width = 1024;
      int height = 1024;
      int bytes = 0;

      try {
        final imgResp = await http.get(Uri.parse(foundImageUrl)).timeout(
              const Duration(seconds: 45),
            );
        if (imgResp.statusCode == 200) {
          bytes = imgResp.bodyBytes.length;
          final decoded = img.decodeImage(imgResp.bodyBytes);
          if (decoded != null) {
            width = decoded.width;
            height = decoded.height;
          }
        }
      } catch (_) {}

      final totalEnd = DateTime.now();
      final renderDuration = totalEnd.difference(renderStart ?? submitEnd);
      final queueDuration = (renderStart ?? submitEnd).difference(submitEnd);

      return GenerationResult(
        imageUrl: foundImageUrl,
        width: width,
        height: height,
        bytes: bytes,
        format: format ?? 'png',
        modelId: modelId ?? 'dola-seedream-3',
        seed: seed,
        requestId: 'dola_${DateTime.now().millisecondsSinceEpoch}',
        quotaRemaining: null,
        quotaLimit: null,
        prompt: prompt,
        timing: GenerationTiming(
          submit: submitDuration,
          queued: queueDuration,
          render: renderDuration,
        ),
      );
    } finally {
      client.close();
    }
  }

  /// Generates an image using reference images (image-to-image).
  Future<GenerationResult> imageToImage({
    required String prompt,
    String? modelId,
    required List<String> referenceUrls,
    required String aspectRatio,
    required String resolution,
    required String format,
    int? seed,
    void Function(String status)? onStatus,
    void Function(String status, Duration elapsed)? onProgress,
  }) async {
    // For Dola web, we formulate the prompt with reference URLs and instructions
    final refText = referenceUrls.isNotEmpty
        ? 'Using these reference styles/images: ${referenceUrls.join(', ')}. $prompt'
        : prompt;

    return textToImage(
      prompt: refText,
      modelId: modelId,
      aspectRatio: aspectRatio,
      resolution: resolution,
      format: format,
      seed: seed,
      onStatus: onStatus,
      onProgress: onProgress,
    );
  }

  /// Generates an image using Dola AI text-to-image with account pooling & automatic failover.
  static Future<GenerationResult> textToImageWithPool({
    required String prompt,
    String? modelId,
    String? aspectRatio,
    String? resolution,
    String? format,
    int? seed,
    void Function(String status)? onStatus,
    void Function(String status, Duration elapsed)? onProgress,
  }) async {
    final pool = DolaPool.instance;
    if (pool.isEmpty) {
      final single = await DolaStore.load();
      if (!single.isValid) {
        throw const DolaApiException(
            'No Dola accounts found. Please add Dola cookies in Settings.');
      }
      return DolaApi(single).textToImage(
        prompt: prompt,
        modelId: modelId,
        aspectRatio: aspectRatio,
        resolution: resolution,
        format: format,
        seed: seed,
        onStatus: onStatus,
        onProgress: onProgress,
      );
    }

    final totalAccounts = pool.count;
    dynamic lastError;

    for (var attempt = 0; attempt < totalAccounts; attempt++) {
      final session = pool.nextSession();
      if (session == null || !session.isValid) continue;

      if (totalAccounts > 1) {
        onStatus?.call('Using account ${pool.currentIndex + 1}/$totalAccounts...');
      }

      try {
        final api = DolaApi(session);
        return await api.textToImage(
          prompt: prompt,
          modelId: modelId,
          aspectRatio: aspectRatio,
          resolution: resolution,
          format: format,
          seed: seed,
          onStatus: onStatus,
          onProgress: onProgress,
        );
      } catch (e) {
        lastError = e;
        if (attempt < totalAccounts - 1) {
          onStatus?.call('Account failed, trying next account in pool...');
        }
      }
    }

    throw lastError ?? const DolaApiException('All Dola pool accounts failed.');
  }

  /// Generates an image using reference images with account pooling & automatic failover.
  static Future<GenerationResult> imageToImageWithPool({
    required String prompt,
    String? modelId,
    required List<String> referenceUrls,
    required String aspectRatio,
    required String resolution,
    required String format,
    int? seed,
    void Function(String status)? onStatus,
    void Function(String status, Duration elapsed)? onProgress,
  }) async {
    final pool = DolaPool.instance;
    if (pool.isEmpty) {
      final single = await DolaStore.load();
      if (!single.isValid) {
        throw const DolaApiException(
            'No Dola accounts found. Please add Dola cookies in Settings.');
      }
      return DolaApi(single).imageToImage(
        prompt: prompt,
        modelId: modelId,
        referenceUrls: referenceUrls,
        aspectRatio: aspectRatio,
        resolution: resolution,
        format: format,
        seed: seed,
        onStatus: onStatus,
        onProgress: onProgress,
      );
    }

    final totalAccounts = pool.count;
    dynamic lastError;

    for (var attempt = 0; attempt < totalAccounts; attempt++) {
      final session = pool.nextSession();
      if (session == null || !session.isValid) continue;

      if (totalAccounts > 1) {
        onStatus?.call('Using account ${pool.currentIndex + 1}/$totalAccounts...');
      }

      try {
        final api = DolaApi(session);
        return await api.imageToImage(
          prompt: prompt,
          modelId: modelId,
          referenceUrls: referenceUrls,
          aspectRatio: aspectRatio,
          resolution: resolution,
          format: format,
          seed: seed,
          onStatus: onStatus,
          onProgress: onProgress,
        );
      } catch (e) {
        lastError = e;
        if (attempt < totalAccounts - 1) {
          onStatus?.call('Account failed, trying next account in pool...');
        }
      }
    }

    throw lastError ?? const DolaApiException('All Dola pool accounts failed.');
  }

  static String _buildQueryParams(int nowMs) {
    return 'device_platform=android&os=android&ssmix=a'
        '&cdid=ee3c4d85-c8f0-4c57-8027-1ec83293a5d5&channel=googleplay&aid=489823'
        '&app_name=nova_ai&version_code=14080001&version_name=14.8.0'
        '&manifest_version_code=14080005&update_version_code=14080040'
        '&resolution=1080*2186&dpi=420&device_type=SM-A525M&device_brand=samsung'
        '&language=en&os_api=34&os_version=14&ac=wifi'
        '&app_language=en&carrier_region=us&flow_app_variant=cici'
        '&sys_region=US&tz_name=America%2FNew_York'
        '&user_is_login=1&is_new_user=0&region=US&lang=en&pkg_type=release_version'
        '&iid=7681561912517068597&device_id=7681452747673093652&flow_sdk_version=14080040'
        '&flow_im_arch=v2&is_retry=0';
  }

  Map<String, String> _buildWebHeaders() {
    return {
      'Host': 'www.dola.com',
      'Origin': 'https://www.dola.com',
      'Referer': 'https://www.dola.com/chat/',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
      'Cookie': session.cookieHeader,
    };
  }

  Map<String, String> _buildAppHeaders(int nowMs, Map<String, String> sig) {
    return {
      'Host': 'api16-normal-i18n-myb.dola.com',
      'Connection': 'keep-alive',
      'Cookie': session.cookieHeader,
      'X-OMNI-REQUEST': '1',
      'sdk-version': '2',
      'passport-sdk-settings': 'device_transfer_s_0,device_transfer_ab_0',
      'passport-sdk-version': '60592',
      'Content-Type': 'application/json; encoding=utf-8',
      'x-tt-store-region': session.carrierRegion,
      'x-tt-store-region-src': 'uid',
      'X-SS-DP': '489823',
      'User-Agent':
          'com.larus.wolf/14080005 (Linux; U; Android 14; en_US; SM-A525M; Build/UP1A.231005.007; Cronet/TTNetVersion:f5f9daf9)',
      'X-SS-REQ-TICKET': nowMs.toString(),
      'X-Gorgon': sig['X-Gorgon'] ?? '',
      'X-Khronos': sig['X-Khronos'] ?? '',
      'X-Ladon': sig['X-Ladon'] ?? DolaSigner.sessionFixed,
    };
  }

  Map<String, dynamic> _buildPayload({
    required String text,
    required String conversationId,
    required int lastMessageIndex,
    required String lastSectionId,
    required String localConvId,
  }) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final msgId = 'ais_${Random().nextInt(10000000)}';
    final uidPrefix = session.uid.isNotEmpty ? session.uid : 'dola_user';

    return {
      'client_meta': {
        'biz_type': '',
        'bot_id': _botId,
        'conversation_id': conversationId,
        'history_message_list': [],
        'last_message_index': lastMessageIndex,
        'last_section_id': lastSectionId,
        'local_conversation_id': localConvId.isNotEmpty ? localConvId : 'ais_$nowMs',
        'scene_type': 0,
        'section_id': '',
      },
      'ext': {
        'answer_with_suggest': '1',
        'create_time_ms': nowMs.toString(),
        'send_message_scene': 'keyboard',
        'system_language': 'en',
      },
      'messages': [
        {
          'content_block': [
            {
              'append_fields': [],
              'block_id': 'blk_$msgId',
              'block_type': 10000,
              'content': {
                'text_block': {'text': text, 'text_block_scene': 0}
              },
              'is_finish': false,
              'meta_info': [],
              'parent_id': '',
            }
          ],
          'local_message_id': msgId,
          'message_specific_ext': {
            'before_content_type': 1,
            'send_message_scene': 'keyboard'
          },
          'message_status': 0,
        }
      ],
      'option': {
        'ab_launch_only': false,
        'agent_mode': 2,
        'answer_with_suggest': true,
        'click_clear_context': false,
        'unique_key': '${uidPrefix}_$msgId',
      },
    };
  }

  static String? _extractTextFromJson(String? event, dynamic json) {
    if (json is! Map) return null;
    if (event == 'STREAM_MSG_NOTIFY') {
      final blocks = json['content']?['content_block'];
      if (blocks is List) {
        final buffer = StringBuffer();
        for (final b in blocks) {
          final t = b['content']?['text_block']?['text'];
          if (t != null) buffer.write(t.toString());
        }
        return buffer.isNotEmpty ? buffer.toString() : null;
      }
    } else if (event == 'STREAM_CHUNK') {
      final ops = json['patch_op'];
      if (ops is List) {
        final buffer = StringBuffer();
        for (final op in ops) {
          final blocks = op['patch_value']?['content_block'];
          if (blocks is List) {
            for (final b in blocks) {
              final t = b['content']?['text_block']?['text'];
              if (t != null) buffer.write(t.toString());
            }
          }
        }
        return buffer.isNotEmpty ? buffer.toString() : null;
      }
    }
    return null;
  }

  static String? _extractImageUrlFromJson(String? event, dynamic json) {
    if (json is! Map) return null;

    // Recursive search for known ByteDance / Dola image URLs or attachments
    String? checkValue(dynamic val) {
      if (val is String) {
        if (val.contains('.ibyteimg.com') ||
            val.contains('.ciciai.com') ||
            val.contains('.dola.com') ||
            val.contains('.doubao.com') ||
            val.contains('tos-') ||
            (val.startsWith('http') &&
                (val.contains('.png') ||
                    val.contains('.jpg') ||
                    val.contains('.jpeg') ||
                    val.contains('.webp')))) {
          return val;
        }
      } else if (val is Map) {
        // Direct image properties
        for (final k in ['origin_url', 'tiny_url', 'url', 'uri', 'download_url']) {
          final v = val[k];
          if (v is String && v.startsWith('http')) {
            return v;
          }
        }
        if (val['image_ori'] is Map) {
          final u = val['image_ori']['url'];
          if (u is String && u.startsWith('http')) return u;
        }
        if (val['image_thumb'] is Map) {
          final u = val['image_thumb']['url'];
          if (u is String && u.startsWith('http')) return u;
        }
        for (final sub in val.values) {
          final found = checkValue(sub);
          if (found != null) return found;
        }
      } else if (val is List) {
        for (final sub in val) {
          final found = checkValue(sub);
          if (found != null) return found;
        }
      }
      return null;
    }

    return checkValue(json);
  }

  static String? _findImageUrlInText(String text) {
    // 1. Markdown image regex: ![...](https://...)
    final mdMatch = RegExp(r'!\[.*?\]\((https?://[^\s\)]+)\)').firstMatch(text);
    if (mdMatch != null) return mdMatch.group(1);

    // 2. Direct ByteDance / Dola CDN image URL
    final cdnMatch = RegExp(
            r'''https?://[^\s"'<>)]+?(?:ibyteimg\.com|ciciai\.com|dola\.com)[^\s"'<>)]*?(?:\.png|\.jpg|\.jpeg|\.webp|~tplv[^\s"'<>)]*)''',
            caseSensitive: false)
        .firstMatch(text);
    if (cdnMatch != null) return cdnMatch.group(0);

    // 3. Any standard web image URL
    final anyImgMatch = RegExp(
            r'''https?://[^\s"'<>)]+?\.(?:png|jpg|jpeg|webp)(?:\?[^\s"'<>)]*)?''',
            caseSensitive: false)
        .firstMatch(text);
    if (anyImgMatch != null) return anyImgMatch.group(0);

    return null;
  }
}

