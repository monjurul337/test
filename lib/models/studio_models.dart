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
  final String osType; // Android, Windows, Linux, macOS
  final String navPlatform;
  final String userAgent;
  final String webglVendor;
  final String webglRenderer;
  final int hardwareConcurrency;
  final int deviceMemory;
  final String timezone;

  const FingerprintProfile({
    required this.seed,
    required this.osType,
    required this.navPlatform,
    required this.userAgent,
    required this.webglVendor,
    required this.webglRenderer,
    required this.hardwareConcurrency,
    required this.deviceMemory,
    required this.timezone,
  });

  factory FingerprintProfile.defaultAndroid(int seed, {String osType = 'Android'}) {
    if (osType == 'Windows') {
      const gpus = [
        ('Google Inc. (NVIDIA)', 'ANGLE (NVIDIA, NVIDIA GeForce RTX 3060 Direct3D11 vs_5_0 ps_5_0, D3D11)', 12, 16),
        ('Google Inc. (NVIDIA)', 'ANGLE (NVIDIA, NVIDIA GeForce GTX 1660 SUPER Direct3D11 vs_5_0 ps_5_0, D3D11)', 8, 16),
        ('Google Inc. (Intel)', 'ANGLE (Intel, Intel(R) UHD Graphics 770 Direct3D11 vs_5_0 ps_5_0, D3D11)', 8, 8),
        ('Google Inc. (AMD)', 'ANGLE (AMD, AMD Radeon RX 6600 Direct3D11 vs_5_0 ps_5_0, D3D11)', 12, 32),
      ];
      final g = gpus[seed % gpus.length];
      return FingerprintProfile(
        seed: seed,
        osType: 'Windows',
        navPlatform: 'Win32',
        // Keep mobile UA for WebView layout fit while JS spoofs Win32 + desktop GPU/Client Hints
        userAgent: 'Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.6723.102 Mobile Safari/537.36',
        webglVendor: g.$1,
        webglRenderer: g.$2,
        hardwareConcurrency: g.$3,
        deviceMemory: g.$4,
        timezone: 'Asia/Dhaka',
      );
    }
    if (osType == 'Linux') {
      const gpus = [
        ('Mesa', 'Mesa Intel(R) Iris(R) Xe Graphics (ADL GT2)', 8, 16),
        ('NVIDIA Corporation', 'NVIDIA GeForce RTX 3070/PCIe/SSE2', 16, 32),
        ('AMD', 'AMD Radeon RX 6700 XT (navi22, LLVM 17.0.6)', 12, 16),
      ];
      final g = gpus[seed % gpus.length];
      return FingerprintProfile(
        seed: seed,
        osType: 'Linux',
        navPlatform: 'Linux x86_64',
        userAgent: 'Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.6723.102 Mobile Safari/537.36',
        webglVendor: g.$1,
        webglRenderer: g.$2,
        hardwareConcurrency: g.$3,
        deviceMemory: g.$4,
        timezone: 'Asia/Dhaka',
      );
    }
    if (osType == 'macOS') {
      const gpus = [
        ('Apple Inc.', 'Apple M2 Pro', 10, 16),
        ('Apple Inc.', 'Apple M3', 8, 16),
        ('Apple Inc.', 'Apple M1 Max', 10, 32),
      ];
      final g = gpus[seed % gpus.length];
      return FingerprintProfile(
        seed: seed,
        osType: 'macOS',
        navPlatform: 'MacIntel',
        userAgent: 'Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.6723.102 Mobile Safari/537.36',
        webglVendor: g.$1,
        webglRenderer: g.$2,
        hardwareConcurrency: g.$3,
        deviceMemory: g.$4,
        timezone: 'Asia/Dhaka',
      );
    }

    const profiles = [
      ('Android 14', 'Pixel 8 Pro', '130.0.6723.102', 'ARM', 'Mali-G715 MC7', 8, 12),
      ('Android 15', 'SM-S928B', '131.0.6778.81', 'Qualcomm', 'Adreno (TM) 750', 8, 12),
      ('Android 14', 'CPH2581', '129.0.6668.100', 'Qualcomm', 'Adreno (TM) 750', 8, 16),
      ('Android 13', '23127PN0CG', '128.0.6613.146', 'Qualcomm', 'Adreno (TM) 740', 8, 8),
      ('Android 14', 'SM-A556B', '130.0.6723.58', 'ARM', 'Xclipse 530', 8, 8),
      ('Android 15', 'Pixel 9', '131.0.6778.39', 'ARM', 'Mali-G715 MC7', 8, 12),
    ];
    final p = profiles[seed % profiles.length];
    return FingerprintProfile(
      seed: seed,
      osType: 'Android',
      navPlatform: 'Linux armv8l',
      userAgent:
          'Mozilla/5.0 (Linux; ${p.$1}; ${p.$2}) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/${p.$3} Mobile Safari/537.36',
      webglVendor: p.$4,
      webglRenderer: p.$5,
      hardwareConcurrency: p.$6,
      deviceMemory: p.$7,
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

class StockSaleItem {
  final String title;
  final String amount;
  final String info;
  final String thumbUrl;

  const StockSaleItem({
    required this.title,
    required this.amount,
    required this.info,
    this.thumbUrl = '',
  });

  factory StockSaleItem.fromJson(Map<String, dynamic> j) => StockSaleItem(
        title: (j['title'] ?? 'Asset').toString(),
        amount: (j['amount'] ?? r'$0.00').toString(),
        info: (j['info'] ?? '').toString(),
        thumbUrl: (j['thumbUrl'] ?? '').toString(),
      );
}

class StockPayoutItem {
  final String date;
  final String amount;
  final String status;

  const StockPayoutItem({required this.date, required this.amount, required this.status});

  factory StockPayoutItem.fromJson(Map<String, dynamic> j) => StockPayoutItem(
        date: (j['date'] ?? '').toString(),
        amount: (j['amount'] ?? r'$0.00').toString(),
        status: (j['status'] ?? 'Paid').toString(),
      );
}

class StockDashboardStats {
  final int inReview;
  final int totalFiles;
  final int downloads;
  final String earnings;
  final int withdrawCount;
  final String totalWithdrawn;
  final List<StockSaleItem> recentSales;
  final List<StockPayoutItem> payouts;
  final List<double> chartPoints;

  const StockDashboardStats({
    this.inReview = 0,
    this.totalFiles = 0,
    this.downloads = 0,
    this.earnings = r'$0.00',
    this.withdrawCount = 0,
    this.totalWithdrawn = r'$0.00',
    this.recentSales = const [],
    this.payouts = const [],
    this.chartPoints = const [0, 0, 0, 0, 0, 0, 0],
  });

  factory StockDashboardStats.fromJson(Map<String, dynamic> j) => StockDashboardStats(
        inReview: (j['inReview'] as num?)?.toInt() ?? 0,
        totalFiles: (j['totalFiles'] as num?)?.toInt() ?? (j['approved'] as num?)?.toInt() ?? 0,
        downloads: (j['downloads'] as num?)?.toInt() ?? 0,
        earnings: (j['earnings'] ?? r'$0.00').toString(),
        withdrawCount: (j['withdrawCount'] as num?)?.toInt() ?? 0,
        totalWithdrawn: (j['totalWithdrawn'] ?? r'$0.00').toString(),
        recentSales: (j['recentSales'] as List? ?? [])
            .map((e) => StockSaleItem.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        payouts: (j['payouts'] as List? ?? [])
            .map((e) => StockPayoutItem.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        chartPoints: (j['chartPoints'] as List? ?? [0, 0, 0, 0, 0, 0, 0])
            .map((e) => (e as num?)?.toDouble() ?? 0.0)
            .toList(),
      );
}
