import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gemini_hd_studio/chrome_cdp.dart';

void main() {
  group('CDP wire format', () {
    test('encodeCdpRequest includes id/method/params/sessionId', () {
      final s = encodeCdpRequest(
        3,
        'Page.navigate',
        params: {'url': 'https://example.com'},
        sessionId: 'S1',
      );
      final j = jsonDecode(s) as Map<String, dynamic>;
      expect(j['id'], 3);
      expect(j['method'], 'Page.navigate');
      expect((j['params'] as Map)['url'], 'https://example.com');
      expect(j['sessionId'], 'S1');
    });

    test('decodeCdpFrame parses an event, a response, and junk', () {
      final ev = decodeCdpFrame(
          '{"method":"Runtime.bindingCalled","params":{"name":"geminiBridge","payload":"[]"},"sessionId":"S1"}');
      expect(ev, isNotNull);
      expect(ev!.isEvent, isTrue);
      expect(ev.params['name'], 'geminiBridge');
      expect(ev.sessionId, 'S1');

      final res = decodeCdpFrame('{"id":7,"result":{"targetId":"T1"}}');
      expect(res, isNotNull);
      expect(res!.id, 7);
      expect(res.result!['targetId'], 'T1');

      expect(decodeCdpFrame('not json'), isNull);
      expect(decodeCdpFrame('[1,2]'), isNull);
    });
  });

  group('CDP cookie conversion', () {
    test('cookieHeaderFromCdp keeps matching domains, last name wins', () {
      final header = cookieHeaderFromCdp(
        [
          const CdpCookie(name: 'A', value: '1', domain: '.google.com'),
          const CdpCookie(name: 'B', value: '2', domain: '.pinterest.com'),
          const CdpCookie(
              name: 'A', value: '3', domain: 'accounts.google.com'),
          const CdpCookie(name: 'C', value: '4', domain: 'google.com'),
        ],
        ['google.com'],
      );
      expect(header, 'A=3; C=4');
    });

    test('cdpCookiesFromHeader parses pairs, skips junk', () {
      final cookies =
          cdpCookiesFromHeader('__Secure-1PSID=abc; SID=xyz; junk; =no');
      expect(cookies.length, 2);
      expect(cookies.first.name, '__Secure-1PSID');
      expect(cookies.first.value, 'abc');
      expect(cookies.first.httpOnly, isTrue);
      expect(cookies.first.domain, '.google.com');
      expect(cookies.last.name, 'SID');
      expect(cookies.last.httpOnly, isFalse);
    });

    test('CdpCookie JSON round-trip keeps fields', () {
      const c = CdpCookie(
        name: 'SID',
        value: 'v',
        domain: '.google.com',
        path: '/',
        secure: true,
        httpOnly: true,
        expires: 1893456000,
      );
      final back = CdpCookie.fromJson(c.toJson());
      expect(back.name, 'SID');
      expect(back.value, 'v');
      expect(back.httpOnly, isTrue);
      expect(back.expires, 1893456000);
    });
  });
}
