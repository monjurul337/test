import 'package:flutter_test/flutter_test.dart';
import 'package:pc_assistant/command_parser.dart';

void main() {
  test('youtube opens youtube', () {
    expect(parseCommand('open youtube')[0], 'OPEN_URL');
  });
  test('screenshot in bangla', () {
    expect(parseCommand('স্ক্রিনশট নাও')[0], 'SCREENSHOT');
  });
  test('notepad opens app', () {
    expect(parseCommand('open notepad'), ['OPEN_APP', 'notepad']);
  });
  test('cancel shutdown wins over shutdown', () {
    expect(parseCommand('cancel shutdown')[0], 'CANCEL_SHUTDOWN');
  });
}
