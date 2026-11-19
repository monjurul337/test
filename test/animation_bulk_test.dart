// v93 — Animation bulk generate: a queue of prompts run one
// after another through the same start() as a single generation
// (backend first in Task mode, browser fallback inside).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gemini_hd_studio/animation_engine.dart';
import 'package:gemini_hd_studio/animation_models.dart';
import 'package:gemini_hd_studio/gecko_browser.dart';
import 'package:gemini_hd_studio/task_backend.dart';

GeckoBrowserRequest _videoReq(String action, Map<String, dynamic> data) =>
    GeckoBrowserRequest(action, const [], 'https://gemini.google.com/app',
        'Gemini',
        data: data);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('v93: bulk queue models', () {
    test('parseBulkPrompts: one prompt per line, blanks dropped', () {
      expect(parseBulkPrompts('a\n\n  \n b \n'), ['a', 'b']);
      expect(parseBulkPrompts(''), isEmpty);
      expect(parseBulkPrompts('  one line  '), ['one line']);
    });

    test('BulkQueueItem status text', () {
      final item = BulkQueueItem(id: '1', rawPrompt: 'golden phone');
      expect(item.status, BulkItemStatus.queued);
      expect(item.statusText, 'Waiting');
      expect(item.shortPrompt, 'golden phone');
      item.status = BulkItemStatus.failed;
      item.error = 'time out';
      expect(item.statusText, 'Hoyni: time out');
    });
  });

  group('v93: bulk run (engine)', () {
    late Directory tmp;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      tmp = Directory.systemTemp.createTempSync('anim93-test-');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async {
          if (call.method == 'getApplicationDocumentsDirectory' ||
              call.method == 'getTemporaryDirectory') {
            return tmp.path;
          }
          return null;
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    AnimationEngine engineWith({
      List<String>? opened,
      List<Map<String, String>>? jobs,
      TaskBackendRunner? runner,
    }) {
      final engine = AnimationEngine(
        openBrowser: (url) async {
          opened?.add(url);
        },
        sendVideoJob: (prompt, modelId, jobId) async {
          jobs?.add(
              {'prompt': prompt, 'model': modelId, 'jobId': jobId});
        },
        taskBackendRunner: runner,
        jobTimeout: const Duration(seconds: 5),
      );
      return engine;
    }

    test('bulk happy path: 2 prompts -> 2 videos, runner x2, no browser',
        () async {
      var runnerCalls = 0;
      final opened = <String>[];
      final engine = engineWith(
        opened: opened,
        runner: (taskText, {required onPhase, required deadline}) async {
          runnerCalls++;
          return Uint8List.fromList([1, 2, 3, 4, 5]);
        },
      );
      await engine.load();
      engine.addBulkPrompts(['golden phone charging', 'neon energy phone']);
      expect(engine.bulkQueue.length, 2);
      expect(await engine.startBulk(signedIn: true), isTrue);
      expect(runnerCalls, 2);
      expect(opened, isEmpty);
      expect(engine.videos.length, 2);
      expect(engine.bulkDoneCount, 2);
      expect(engine.bulkFailedCount, 0);
      expect(engine.bulkRunning, isFalse);
      expect(engine.bulkStatus, contains('Bulk sesh: 2/2'));
    });

    test('bulk continues after one item fails', () async {
      final engine = engineWith(
        runner: (taskText, {required onPhase, required deadline}) async {
          if (taskText.startsWith('bad prompt')) {
            throw const TaskBackendException(
                'task', 'Gemini error diyeche.');
          }
          return Uint8List.fromList([1, 2, 3]);
        },
      );
      await engine.load();
      engine.addBulkPrompts(['good prompt one', 'bad prompt two']);
      expect(await engine.startBulk(signedIn: true), isTrue);
      expect(engine.bulkDoneCount, 1);
      expect(engine.bulkFailedCount, 1);
      expect(engine.videos.length, 1);
      expect(engine.bulkQueue[1].status, BulkItemStatus.failed);
    });

    test('bulk: copyright-risk item fails without calling the runner',
        () async {
      var runnerCalls = 0;
      final engine = engineWith(
        runner: (taskText, {required onPhase, required deadline}) async {
          runnerCalls++;
          return Uint8List.fromList([1, 2, 3]);
        },
      );
      await engine.load();
      engine.addBulkPrompts(['make an iPhone ad video']);
      expect(await engine.startBulk(signedIn: true), isTrue);
      expect(runnerCalls, 0);
      expect(engine.bulkFailedCount, 1);
      expect(engine.bulkQueue[0].error, contains('Copyright'));
      expect(engine.videos, isEmpty);
    });

    test('bulk: cancel stops after the current video', () async {
      final firstDone = Completer<Uint8List>();
      final engine = engineWith(
        runner: (taskText, {required onPhase, required deadline}) async {
          if (taskText.startsWith('first prompt')) {
            return firstDone.future;
          }
          return Uint8List.fromList([9, 9, 9]);
        },
      );
      await engine.load();
      engine.addBulkPrompts(
          ['first prompt', 'second prompt', 'third prompt']);
      final run = engine.startBulk(signedIn: true);
      // Wait until the first item is actually running.
      for (var i = 0;
          i < 50 && engine.bulkQueue[0].status != BulkItemStatus.running;
          i++) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
      expect(engine.bulkQueue[0].status, BulkItemStatus.running);
      engine.cancelBulk();
      firstDone.complete(Uint8List.fromList([1, 2, 3]));
      expect(await run, isTrue);
      expect(engine.bulkQueue[0].status, BulkItemStatus.done);
      expect(engine.bulkQueue[1].status, BulkItemStatus.queued);
      expect(engine.bulkQueue[2].status, BulkItemStatus.queued);
      expect(engine.videos.length, 1);
    });

    test('bulk with Task mode off uses the browser driver per item',
        () async {
      final opened = <String>[];
      final jobs = <Map<String, String>>[];
      late AnimationEngine engine;
      engine = engineWith(
        opened: opened,
        jobs: jobs,
        runner: (taskText, {required onPhase, required deadline}) async {
          throw StateError('backend must not run with Task mode off');
        },
      );
      await engine.load();
      engine.taskMode = false;
      engine.addBulkPrompts(['phone one', 'phone two']);
      // The fake driver answers video_ready for each job as soon
      // as it is sent (data-URL MP4 bytes), so the run finishes
      // without waiting out the 5s job timeout per item.
      final run = engine.startBulk(signedIn: true);
      for (var i = 0; i < 100 && engine.videos.length < 2; i++) {
        await Future.delayed(const Duration(milliseconds: 20));
        if (jobs.isNotEmpty) {
          final job = jobs.removeAt(0);
          await engine.handleRequest(_videoReq('video_ready', {
            'jobId': job['jobId']!,
            'dataUrl':
                'data:video/mp4;base64,${base64Encode([1, 2, 3, 4, 5])}',
          }));
        }
      }
      expect(await run, isTrue);
      expect(opened.length, 2);
      expect(engine.videos.length, 2);
      expect(engine.bulkDoneCount, 2);
    });

    test('bulk: empty queue + not signed in refuse to start', () async {
      final engine = engineWith();
      await engine.load();
      expect(await engine.startBulk(signedIn: true), isFalse);
      engine.addBulkPrompts(['one prompt']);
      expect(await engine.startBulk(signedIn: false), isFalse);
      expect(engine.bulkQueue[0].status, BulkItemStatus.queued);
    });
  });
}
