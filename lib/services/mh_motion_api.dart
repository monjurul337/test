import 'dart:io';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:path_provider/path_provider.dart';
import '../models/studio_models.dart';

class MhMotionApi {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(minutes: 5),
  ));
  final CookieJar _cookieJar = CookieJar();
  String _baseUrl = '';

  MhMotionApi() {
    _dio.interceptors.add(CookieManager(_cookieJar));
  }

  String get baseUrl => _baseUrl;
  bool get isConfigured => _baseUrl.isNotEmpty;

  void setBaseUrl(String url) {
    _baseUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
  }

  Future<ServerInfo> connect({required String url, String password = ''}) async {
    setBaseUrl(url);
    if (password.isNotEmpty) {
      await _dio.post(
        '$_baseUrl/login',
        data: {'password': password},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          followRedirects: false,
          validateStatus: (s) => s != null && s < 400,
        ),
      );
    }
    final res = await _dio.get('$_baseUrl/api/info');
    return ServerInfo.fromJson(Map<String, dynamic>.from(res.data));
  }

  Future<List<String>> listScenes() async {
    final res = await _dio.get('$_baseUrl/api/scenes');
    return List<String>.from(res.data['scenes'] ?? []);
  }

  Future<String> loadScene(String name) async {
    final res = await _dio.get('$_baseUrl/api/scene', queryParameters: {'name': name});
    return (res.data['code'] ?? '').toString();
  }

  Future<void> saveScene(String name, String code) async {
    await _dio.post('$_baseUrl/api/scene', data: {'name': name, 'code': code});
  }

  Future<(bool, String)> checkShader(String code) async {
    final res = await _dio.post('$_baseUrl/api/check', data: {'code': code});
    return (res.data['ok'] == true, (res.data['log'] ?? '').toString());
  }

  Future<String?> renderStill(String code, {int width = 1280, int height = 720}) async {
    final res = await _dio.post('$_baseUrl/api/still', data: {
      'code': code,
      'width': width,
      'height': height,
    });
    if (res.data['ok'] == true) {
      return '$_baseUrl/out/${Uri.encodeComponent(res.data['file'])}';
    }
    throw Exception(res.data['error'] ?? 'Snapshot failed');
  }

  Future<void> startRender({
    required String scene,
    required String code,
    int width = 1920,
    int height = 1080,
    int fps = 30,
    double duration = 8,
    String codec = 'h264',
    String encoder = 'gpu',
    String quality = 'high',
    bool quickTest = false,
    bool addMusic = false,
  }) async {
    await _dio.post('$_baseUrl/api/render', data: {
      'scene': scene,
      'code': code,
      'width': width,
      'height': height,
      'fps': fps,
      'duration': duration,
      'codec': codec,
      'encoder': encoder,
      'quality': quality,
      'quick': quickTest,
      'music': addMusic,
    });
  }

  Future<RenderJob> getJobStatus() async {
    final res = await _dio.get('$_baseUrl/api/job');
    return RenderJob.fromJson(Map<String, dynamic>.from(res.data));
  }

  Future<void> cancelRender() async {
    await _dio.post('$_baseUrl/api/cancel');
  }

  Future<List<OutputVideo>> listOutputs() async {
    final res = await _dio.get('$_baseUrl/api/outputs');
    final list = res.data['outputs'] as List? ?? [];
    return list
        .map((e) => OutputVideo.fromJson(Map<String, dynamic>.from(e)))
        .where((v) => v.name.toLowerCase().endsWith('.mp4'))
        .toList();
  }

  Future<void> deleteOutput(String name) async {
    await _dio.post('$_baseUrl/api/delete', data: {'name': name});
  }

  Future<File> downloadOutput(
    String fileName, {
    void Function(int received, int total)? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final savePath = '${dir.path}/$fileName';
    await _dio.download(
      '$_baseUrl/out/${Uri.encodeComponent(fileName)}?dl=1',
      savePath,
      onReceiveProgress: onProgress,
    );
    return File(savePath);
  }
}
