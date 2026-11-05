import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

// =====================================================================
//  এই app-এর ভিতরেই পুরো Signtech Digital software bundle করা আছে
//  (assets/www/index.html) — তাই blog/Blogger লাগবে না, app একাই চলে।
//  Bundled file-টা device-এর localhost দিয়ে চালানো হয়, যাতে
//  login/session ঠিকমতো save থাকে। ডাটা আগের মতোই Firebase cloud-এ —
//  তাই internet লাগবে শুধু data sync-এর জন্য।
//
//  Software update করতে চাইলে: নতুন index.html টা
//  assets/www/index.html হিসেবে replace করে app আবার build করো।
// =====================================================================
const String kHomeUrl = 'http://localhost:8123/index.html';

const Color kBrandRed = Color(0xFFCD242B);
const Color kBg = Color(0xFF0B0B10);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Bundled web app চালানোর জন্য localhost server (blog লাগবে না)
  await InAppLocalhostServer(documentRoot: 'assets/www', port: 8123).start();
  runApp(const SigntechApp());
}

class SigntechApp extends StatelessWidget {
  const SigntechApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Signtech Digital',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: kBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kBrandRed,
          brightness: Brightness.dark,
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  InAppWebViewController? _web;
  PullToRefreshController? _pullToRefresh;
  double _progress = 0;
  bool _loadError = false;
  bool _exitReady = false;

  bool get _isDesktop => !kIsWeb && Platform.isWindows;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && Platform.isAndroid) {
      _pullToRefresh = PullToRefreshController(
        settings: PullToRefreshSettings(color: kBrandRed),
        onRefresh: () async {
          await _web?.reload();
        },
      );
    }
  }

  // WhatsApp / Messenger / phone / mail লিংকগুলো WebView-র ভিতরে না খুলে
  // আসল app-এ (বাইরে) খোলা হয়, যাতে invoice share ঠিকমতো কাজ করে।
  bool _shouldOpenExternally(WebUri url) {
    final scheme = url.scheme.toLowerCase();
    final host = url.host.toLowerCase();
    if (scheme == 'tel' || scheme == 'mailto' || scheme == 'sms') {
      return true;
    }
    if (host.contains('wa.me') ||
        host.contains('api.whatsapp.com') ||
        host.contains('messenger.com') ||
        host.contains('m.me')) {
      return true;
    }
    return false;
  }

  Future<void> _openExternal(WebUri url) async {
    final uri = Uri.parse(url.toString());
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _exitReady,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // Android back button: আগে WebView-র ভিতরে পেছনে যাও,
        // ইতিহাস না থাকলে তবেই app বন্ধ করো।
        final navigator = Navigator.of(context);
        if (_web != null && await _web!.canGoBack()) {
          await _web!.goBack();
        } else {
          setState(() => _exitReady = true);
          navigator.pop();
        }
      },
      child: Scaffold(
        appBar: _isDesktop
            ? AppBar(
                backgroundColor: const Color(0xFF121218),
                title: const Text('Signtech Digital',
                    style: TextStyle(fontSize: 16)),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Back',
                    onPressed: () async {
                      if (_web != null && await _web!.canGoBack()) {
                        await _web!.goBack();
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    tooltip: 'Forward',
                    onPressed: () async {
                      if (_web != null && await _web!.canGoForward()) {
                        await _web!.goForward();
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Reload',
                    onPressed: () => _web?.reload(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.home),
                    tooltip: 'Home',
                    onPressed: () => _web?.loadUrl(
                        urlRequest: URLRequest(url: WebUri(kHomeUrl))),
                  ),
                ],
              )
            : null,
        body: SafeArea(
          child: Stack(
            children: [
              InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(kHomeUrl)),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  databaseEnabled: true,
                  cacheEnabled: true,
                  thirdPartyCookiesEnabled: true,
                  useOnDownloadStart: true,
                  mediaPlaybackRequiresUserGesture: false,
                  allowsInlineMediaPlayback: true,
                  supportZoom: false,
                  builtInZoomControls: false,
                  useHybridComposition: true,
                ),
                pullToRefreshController: _pullToRefresh,
                onWebViewCreated: (controller) {
                  _web = controller;
                },
                shouldOverrideUrlLoading: (controller, action) async {
                  final url = action.request.url;
                  if (url != null && _shouldOpenExternally(url)) {
                    await _openExternal(url);
                    return NavigationActionPolicy.CANCEL;
                  }
                  return NavigationActionPolicy.ALLOW;
                },
                onDownloadStartRequest: (controller, request) async {
                  // Backup JSON / CSV ডাউনলোডগুলো browser-এ পাঠানো হয়।
                  await _openExternal(request.url);
                },
                onLoadStart: (controller, url) {
                  if (mounted) setState(() => _loadError = false);
                },
                onReceivedError: (controller, request, error) {
                  if (request.isForMainFrame ?? false) {
                    if (mounted) setState(() => _loadError = true);
                  }
                },
                onLoadStop: (controller, url) async {
                  await _pullToRefresh?.endRefreshing();
                  if (mounted) setState(() => _progress = 0);
                },
                onProgressChanged: (controller, progress) {
                  if (mounted) {
                    setState(() => _progress = progress / 100);
                  }
                },
              ),
              if (_progress > 0 && _progress < 1)
                Align(
                  alignment: Alignment.topCenter,
                  child: LinearProgressIndicator(
                    value: _progress,
                    color: kBrandRed,
                    backgroundColor: Colors.transparent,
                    minHeight: 3,
                  ),
                ),
              if (_loadError)
                Container(
                  color: kBg,
                  width: double.infinity,
                  height: double.infinity,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.wifi_off,
                          size: 64, color: kBrandRed),
                      const SizedBox(height: 16),
                      const Text(
                        'ইন্টারনেট সংযোগ নেই\nConnection problem — check your internet',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, height: 1.5),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kBrandRed,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 22, vertical: 12),
                        ),
                        onPressed: () {
                          setState(() => _loadError = false);
                          _web?.reload();
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry / আবার চেষ্টা'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
