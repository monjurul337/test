import 'package:flutter_test/flutter_test.dart';
import 'package:ai_image_studio_mh/dola_api.dart';

void main() {
  group('DolaSession parsing', () {
    test('parses Cookie-Editor JSON array export', () {
      const jsonStr = '''
[
  {"name": "sessionid", "value": "test_session_123"},
  {"name": "odin_tt", "value": "odin_val_456"},
  {"name": "sid_guard", "value": "guard_789"},
  {"name": "store-idc", "value": "mya"},
  {"name": "store-country-code", "value": "bd"}
]
''';
      final session = DolaSession.fromString(jsonStr);
      expect(session.isValid, isTrue);
      expect(session.sessionId, 'test_session_123');
      expect(session.odinTt, 'odin_val_456');
      expect(session.storeIdc, 'mya');
      expect(session.carrierRegion, 'bd');
      expect(session.cookieHeader, contains('sessionid=test_session_123'));
      expect(session.cookieHeader, contains('store-idc=mya'));
    });

    test('parses Header string format', () {
      const headerStr =
          'store-idc=maliva; store-country-code=us; sessionid=my_secret_session_abc; odin_tt=odin_xyz';
      final session = DolaSession.fromString(headerStr);
      expect(session.isValid, isTrue);
      expect(session.sessionId, 'my_secret_session_abc');
      expect(session.odinTt, 'odin_xyz');
      expect(session.storeIdc, 'maliva');
      expect(session.carrierRegion, 'us');
    });

    test('handles empty or invalid cookies gracefully', () {
      final session = DolaSession.fromString('');
      expect(session.isValid, isFalse);
      expect(session.sessionId, '');
    });

    test('parses bulk cookies from multiline text file', () {
      const bulkText = '''
# Account 1
sessionid=account_1_sess; odin_tt=odin_1; store-idc=mya; store-country-code=bd

---
# Account 2
sessionid=account_2_sess; odin_tt=odin_2; store-idc=maliva; store-country-code=us

sessionid=account_3_sess; store-idc=alisg
''';
      final sessions = DolaSession.parseBulk(bulkText);
      expect(sessions.length, 3);
      expect(sessions[0].sessionId, 'account_1_sess');
      expect(sessions[0].carrierRegion, 'bd');
      expect(sessions[1].sessionId, 'account_2_sess');
      expect(sessions[1].carrierRegion, 'us');
      expect(sessions[2].sessionId, 'account_3_sess');
    });

    test('parses bulk JSON array of cookie lists', () {
      const bulkJson = '''
[
  [
    {"name": "sessionid", "value": "json_sess_1"},
    {"name": "store-country-code", "value": "us"}
  ],
  [
    {"name": "sessionid", "value": "json_sess_2"},
    {"name": "store-country-code", "value": "bd"}
  ]
]
''';
      final sessions = DolaSession.parseBulk(bulkJson);
      expect(sessions.length, 2);
      expect(sessions[0].sessionId, 'json_sess_1');
      expect(sessions[1].sessionId, 'json_sess_2');
    });

    test('deduplicates duplicate session IDs in bulk import', () {
      const duplicateText = '''
sessionid=same_session_id; store-idc=mya
sessionid=same_session_id; store-idc=mya
sessionid=diff_session_id; store-idc=maliva
''';
      final sessions = DolaSession.parseBulk(duplicateText);
      expect(sessions.length, 2);
    });
  });

  group('DolaPool management', () {
    test('manages multi-account rotation and round-robin', () {
      final pool = DolaPool.instance;
      pool.clear();
      pool.autoRotate = true;

      final s1 = DolaSession.fromString('sessionid=sess_one; store-idc=mya');
      final s2 = DolaSession.fromString('sessionid=sess_two; store-idc=maliva');

      pool.addSession(s1);
      pool.addSession(s2);

      expect(pool.count, 2);
      expect(pool.nextSession()?.sessionId, 'sess_one');
      expect(pool.nextSession()?.sessionId, 'sess_two');
      expect(pool.nextSession()?.sessionId, 'sess_one');

      pool.removeAt(0);
      expect(pool.count, 1);
      expect(pool.nextSession()?.sessionId, 'sess_two');

      pool.clear();
      expect(pool.isEmpty, isTrue);
    });
  });

  group('DolaSigner', () {
    test('generates valid X-Gorgon, X-Khronos, and X-Ladon', () {
      const testUrl =
          'https://api16-normal-i18n-myb.dola.com/chat/completion?device_platform=android&aid=489823';
      final sig = DolaSigner.sign(testUrl, timestamp: 1700000000);

      expect(sig.containsKey('X-Gorgon'), isTrue);
      expect(sig.containsKey('X-Khronos'), isTrue);
      expect(sig.containsKey('X-Ladon'), isTrue);

      expect(sig['X-Khronos'], '1700000000');
      expect(sig['X-Ladon'], DolaSigner.sessionFixed);

      // Gorgon is a 52-char hex string (26 bytes)
      final gorgon = sig['X-Gorgon']!;
      expect(gorgon.length, 52);
      expect(gorgon.startsWith('8404'), isTrue);
    });
  });
}

