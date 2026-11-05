// Signtech Digital — মৌলিক config test.
// (App-এর মূল অংশ WebView, তাই widget test-এ পুরো app না চালিয়ে
//  শুধু config যাচাই করা হয়।)

import 'package:flutter_test/flutter_test.dart';
import 'package:signtech_digital/main.dart';

void main() {
  test('Bundled app home URL points at the localhost server', () {
    final uri = Uri.parse(kHomeUrl);
    expect(uri.scheme, 'http');
    expect(uri.host, 'localhost');
    expect(uri.path, '/index.html');
  });
}
