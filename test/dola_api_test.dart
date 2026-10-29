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

