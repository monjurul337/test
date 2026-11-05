// Signtech Digital — মৌলিক config test.
// (App-এর মূল অংশ WebView, তাই widget test-এ পুরো app না চালিয়ে
//  শুধু config যাচাই করা হয়।)

import 'package:flutter_test/flutter_test.dart';
import 'package:signtech_digital/main.dart';

void main() {
  test('App URL is a valid https address', () {
    final uri = Uri.parse(kAppUrl);
    expect(uri.scheme, 'https');
    expect(uri.host.isNotEmpty, isTrue);
  });
}
