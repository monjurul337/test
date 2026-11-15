import 'dart:io';
class ServerInfo {
  final String gpu;
  final String gl;
  final bool nvenc;
  final bool hevcNvenc;
  final int cores;
  final bool passwordRequired;

  const ServerInfo({
    required this.gpu,
    required this.gl,
    required this.nvenc,
    required this.hevcNvenc,
    required this.cores,
    required this.passwordRequired,
  });

  factory ServerInfo.fromJson(Map<String, dynamic> j) => ServerInfo(
        gpu: (j['gpu'] ?? 'Unknown GPU').toString(),
        gl: (j['gl'] ?? '').toString(),
        nvenc: j['nvenc'] == true,
        hevcNvenc: j['hevcNvenc'] == true,
        cores: (j['cores'] as num?)?.toInt() ?? 0,
        passwordRequired: j['password'] == true,
      );
}

class RenderJob {
  final String status;
  final String stage;
  final double progress;
  final double fps;
  final String? file;
  final String? error;

  const RenderJob({
    required this.status,
    required this.stage,
    required this.progress,
    required this.fps,
    this.file,
    this.error,
  });

  factory RenderJob.fromJson(Map<String, dynamic> j) => RenderJob(
        status: (j['status'] ?? 'idle').toString(),
        stage: (j['stage'] ?? '').toString(),
        progress: (j['progress'] as num?)?.toDouble() ?? 0.0,
        fps: (j['fps'] as num?)?.toDouble() ?? 0.0,
        file: j['file']?.toString(),
        error: j['error']?.toString(),
      );

  bool get isRunning =>
      status == 'starting' || status == 'rendering' || status == 'encoding';
}

class OutputVideo {
  final String name;
  final int sizeBytes;
  final int timestamp;

  const OutputVideo({
    required this.name,
    required this.sizeBytes,
    required this.timestamp,
  });

  factory OutputVideo.fromJson(Map<String, dynamic> j) => OutputVideo(
        name: (j['name'] ?? '').toString(),
        sizeBytes: (j['size'] as num?)?.toInt() ?? 0,
        timestamp: (j['time'] as num?)?.toInt() ?? 0,
      );

  String get formattedSize {
    final mb = sizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

class AdobeMetadata {
  final String title;
  final String category;
  final List<String> keywords;
  final bool isAiGenerated;

  const AdobeMetadata({
    required this.title,
    required this.category,
    required this.keywords,
    this.isAiGenerated = true,
  });

  factory AdobeMetadata.fromJson(Map<String, dynamic> j) {
    final rawTags = j['keywords'] ?? j['tags'] ?? [];
    final tags = rawTags is List
        ? rawTags.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList()
        : rawTags
            .toString()
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
    return AdobeMetadata(
      title: (j['title'] ?? '').toString().trim(),
      category: (j['category'] ?? 'Abstract').toString().trim(),
      keywords: tags.take(49).toList(),
      isAiGenerated: j['isAiGenerated'] ?? true,
    );
  }
}

class FingerprintProfile {
  final int seed;
  final String userAgent;
  final String webglVendor;
  final String webglRenderer;
  final int hardwareConcurrency;
  final int deviceMemory;
  final String timezone;

  const FingerprintProfile({
    required this.seed,
    required this.userAgent,
    required this.webglVendor,
    required this.webglRenderer,
    required this.hardwareConcurrency,
    required this.deviceMemory,
    required this.timezone,
  });

  factory FingerprintProfile.defaultAndroid(int seed) {
    // Windows 10/11 Chrome Anti-Detect Fingerprint (runs silently in background)
    const renderers = [
      'ANGLE (NVIDIA, NVIDIA GeForce RTX 3060 Direct3D11 vs_5_0 ps_5_0, D3D11)',
      'ANGLE (NVIDIA, NVIDIA GeForce GTX 1660 SUPER Direct3D11 vs_5_0 ps_5_0, D3D11)',
      'ANGLE (Intel, Intel(R) UHD Graphics 770 Direct3D11 vs_5_0 ps_5_0, D3D11)',
      'ANGLE (AMD, AMD Radeon RX 6600 Direct3D11 vs_5_0 ps_5_0, D3D11)',
    ];
    const cores = [8, 12, 16];
    const mems = [8, 16, 32];
    return FingerprintProfile(
      seed: seed,
      userAgent:
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
      webglVendor: 'Google Inc. (NVIDIA)',
      webglRenderer: renderers[seed % renderers.length],
      hardwareConcurrency: cores[seed % cores.length],
      deviceMemory: mems[seed % mems.length],
      timezone: 'Asia/Dhaka',
    );
  }
}

class StockQueueItem {
  final String id;
  final File file;
  final String sceneName;
  final String shaderCode;
  AdobeMetadata? metadata;
  String status; // queued, meta_ready, uploading, submitted, error

  StockQueueItem({
    required this.id,
    required this.file,
    required this.sceneName,
    this.shaderCode = '',
    this.metadata,
    this.status = 'queued',
  });
}

class StockDashboardStats {
  final int inReview;
  final int approved;
  final int downloads;
  final String earnings;

  const StockDashboardStats({
    this.inReview = 0,
    this.approved = 0,
    this.downloads = 0,
    this.earnings = r'$0.00',
  });

  factory StockDashboardStats.fromJson(Map<String, dynamic> j) => StockDashboardStats(
        inReview: (j['inReview'] as num?)?.toInt() ?? 0,
        approved: (j['approved'] as num?)?.toInt() ?? 0,
        downloads: (j['downloads'] as num?)?.toInt() ?? 0,
        earnings: (j['earnings'] ?? r'$0.00').toString(),
      );
}
