import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Named cover palettes. Keep the keys in sync with the planner prompt.
class CoverTheme {
  const CoverTheme(this.name, this.sky, this.accent, this.title, this.scene);

  final String name;
  final List<Color> sky;
  final Color accent;
  final Color title;
  final String scene; // town | hills | grid

  static const Map<String, CoverTheme> all = <String, CoverTheme>{
    'ember': CoverTheme(
      'ember',
      <Color>[Color(0xFF1A1040), Color(0xFF3D1B6B), Color(0xFF7B2D8E),
        Color(0xFFC23B6B), Color(0xFFE8663C), Color(0xFFF59E42)],
      Color(0xFFFFD27F), Color(0xFFFFF4E0), 'town',
    ),
    'frost': CoverTheme(
      'frost',
      <Color>[Color(0xFF06121F), Color(0xFF0D2A44), Color(0xFF17496B),
        Color(0xFF2D7A9C), Color(0xFF78C4D4), Color(0xFFD7F0F5)],
      Color(0xFFA8E4F0), Color(0xFFF2FBFF), 'town',
    ),
    'forest': CoverTheme(
      'forest',
      <Color>[Color(0xFF0B1A12), Color(0xFF13301F), Color(0xFF255138),
        Color(0xFF4A7C4E), Color(0xFF9BB86A), Color(0xFFE3D58C)],
      Color(0xFFE8C66A), Color(0xFFFDF6E0), 'hills',
    ),
    'rose': CoverTheme(
      'rose',
      <Color>[Color(0xFF2A0F2E), Color(0xFF56184F), Color(0xFF8F2566),
        Color(0xFFC74B72), Color(0xFFEF8496), Color(0xFFFFD0C4)],
      Color(0xFFFFD9B8), Color(0xFFFFF4F2), 'hills',
    ),
    'slate': CoverTheme(
      'slate',
      <Color>[Color(0xFF070D18), Color(0xFF0B1626), Color(0xFF102033),
        Color(0xFF15293F), Color(0xFF1B3350), Color(0xFF223F61)],
      Color(0xFF4DA3FF), Color(0xFFFFFFFF), 'grid',
    ),
    'sand': CoverTheme(
      'sand',
      <Color>[Color(0xFF2B1D14), Color(0xFF432C1D), Color(0xFF5E4028),
        Color(0xFF8A6238), Color(0xFFBF9154), Color(0xFFE8CF9C)],
      Color(0xFFF0C987), Color(0xFFFFF8EC), 'hills',
    ),
  };

  static CoverTheme of(String name, {required bool fiction}) =>
      all[name] ?? all[fiction ? 'ember' : 'slate']!;
}

/// Everything the cover studio can change without touching the code.
class CoverStyle {
  const CoverStyle({
    this.theme = 'auto',
    this.layout = 'auto',
    this.font = 'auto',
    this.seed = 42,
  });

  /// A key of [CoverTheme.all], or 'auto' to keep the planner's choice.
  final String theme;

  /// auto | center | left | bottom
  final String layout;

  /// auto | serif | sans
  final String font;

  /// Seeds the stars, embers and rooftops, so a reshuffle gives a new look.
  final int seed;

  static const List<String> layouts = <String>[
    'auto', 'center', 'left', 'bottom',
  ];
  static const List<String> fonts = <String>['auto', 'serif', 'sans'];

  CoverStyle copyWith({String? theme, String? layout, String? font, int? seed}) =>
      CoverStyle(
        theme: theme ?? this.theme,
        layout: layout ?? this.layout,
        font: font ?? this.font,
        seed: seed ?? this.seed,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'theme': theme,
        'layout': layout,
        'font': font,
        'seed': seed,
      };

  String get label => '$theme - $layout - $font';
}

/// One option shown in the cover studio.
class CoverVariant {
  CoverVariant(this.style, this.png);
  final CoverStyle style;
  final Uint8List png;
}

class CoverRenderer {
  static const int width = 1600;
  static const int height = 2560;

  /// Renders the cover and returns PNG bytes (1600x2560, the size every
  /// storefront accepts).
  ///
  /// When [art] holds a generated image (see [Prompts.coverArt]) it is used
  /// as the background and only the type is drawn on top; otherwise the
  /// procedural theme scene is drawn as a fallback.
  static Future<Uint8List> render({
    required String title,
    required String subtitle,
    required String series,
    required String tagline,
    required String author,
    required String themeName,
    required bool fiction,
    CoverStyle style = const CoverStyle(),
    Uint8List? art,
  }) async {
    final String resolvedTheme =
        style.theme == 'auto' || style.theme.isEmpty ? themeName : style.theme;
    final CoverTheme t = CoverTheme.of(resolvedTheme, fiction: fiction);
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder,
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
    const double w = 1600;
    const double h = 2560;

    if (art != null && art.isNotEmpty) {
      await _paintArtwork(canvas, art);
    } else {
      // Sky
      final Paint sky = Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          const Offset(0, h),
          t.sky,
          List<double>.generate(t.sky.length, (int i) => i / (t.sky.length - 1)),
        );
      canvas.drawRect(const Rect.fromLTWH(0, 0, w, h), sky);

      final Random rnd = Random(style.seed);

      if (t.scene == 'grid') {
        final Paint g = Paint()
          ..color = kWhite.withValues(alpha: 0.04)
          ..strokeWidth = 1;
        for (double x = 0; x < w; x += 80) {
          canvas.drawLine(Offset(x, 0), Offset(x, h), g);
        }
        for (double y = 0; y < h; y += 80) {
          canvas.drawLine(Offset(0, y), Offset(w, y), g);
        }
      }

      // Stars
      final List<Color> starColors = <Color>[
        t.title, t.accent, const Color(0xFFCBB8FF), const Color(0xFFFFD9C0)
      ];
      for (int i = 0; i < 300; i++) {
        final double x = rnd.nextDouble() * w;
        final double y = rnd.nextDouble() * h * 0.72;
        final double r = <double>[1, 1, 1, 2, 2, 3][rnd.nextInt(6)];
        final Paint p = Paint()
          ..color = starColors[rnd.nextInt(starColors.length)]
              .withValues(alpha: 0.25 + rnd.nextDouble() * 0.7);
        canvas.drawCircle(Offset(x, y), r, p);
      }

      const double base = h * 0.78;

      if (t.scene != 'grid') {
        // Ground and hills
        canvas.drawRect(
            Rect.fromLTWH(0, base, w, h - base), Paint()..color = const Color(0xFF1B1236));
        canvas.drawOval(
            Rect.fromCenter(center: const Offset(w * 0.22, base + 180), width: w * 1.04, height: 460),
            Paint()..color = const Color(0xFF2A1B45).withValues(alpha: 0.85));
        canvas.drawOval(
            Rect.fromCenter(center: const Offset(w * 0.80, base + 200), width: w * 0.96, height: 420),
            Paint()..color = const Color(0xFF241740).withValues(alpha: 0.9));
      }

      if (fiction) {
        // Embers drifting up from the focal point
        for (int i = 0; i < 140; i++) {
          final double x = w / 2 + (rnd.nextDouble() - 0.5) * w * 0.42;
          final double y = h * 0.40 + rnd.nextDouble() * h * 0.32;
          final Paint p = Paint()
            ..color = <Color>[
              t.accent, const Color(0xFFFF9D4D), const Color(0xFFFFCF6B), const Color(0xFFFF7A3C)
            ][rnd.nextInt(4)]
                .withValues(alpha: 0.35 + rnd.nextDouble() * 0.6);
          canvas.drawCircle(Offset(x, y), 2 + rnd.nextInt(4).toDouble(), p);
        }
      }

      if (t.scene == 'town') {
        _drawTown(canvas, base, t, style.seed);
      }
    }

    // ---- Type ----
    const double pad = 110;
    final bool left = switch (style.layout) {
      'left' => true,
      'center' || 'bottom' => false,
      _ => !fiction,
    };
    final TextAlign align = left ? TextAlign.left : TextAlign.center;
    double y = switch (style.layout) {
      'left' => 760,
      'center' => 150,
      'bottom' => h * 0.46,
      _ => left ? 760 : 150,
    };
    final bool serif = switch (style.font) {
      'serif' => true,
      'sans' => false,
      _ => fiction,
    };

    if (series.isNotEmpty) {
      y += _text(canvas, series.toUpperCase(), y,
          size: 38, color: t.accent, align: align, letterSpacing: 9,
          family: 'sans-serif');
      y += 28;
      canvas.drawRect(
          Rect.fromLTWH(left ? pad : (w - 170) / 2, y, left ? 230 : 170, 2),
          Paint()..color = t.accent.withValues(alpha: 0.7));
      y += 50;
    } else if (left) {
      canvas.drawRect(Rect.fromLTWH(pad, y, 230, 2),
          Paint()..color = t.accent.withValues(alpha: 0.7));
      y += 50;
    }

    final double titleSize = title.length < 20
        ? (left ? 180 : 150)
        : title.length < 34
            ? (left ? 144 : 118)
            : (left ? 112 : 92);
    y += _text(canvas, title, y,
        size: titleSize,
        color: t.title,
        align: align,
        family: serif ? 'serif' : 'sans-serif',
        height: 1.05,
        shadow: true);

    if (subtitle.isNotEmpty) {
      y += 40;
      y += _text(canvas, subtitle, y,
          size: left ? 52 : 46,
          color: kWhite.withValues(alpha: 0.92),
          align: align,
          italic: fiction,
          family: serif ? 'serif' : 'sans-serif');
    }
    if (tagline.isNotEmpty) {
      y += 54;
      _text(canvas, tagline, y,
          size: 40,
          color: kWhite.withValues(alpha: 0.85),
          align: align,
          italic: true,
          family: 'serif');
    }

    _text(canvas, author, h - 190,
        size: 62,
        color: t.title,
        align: align,
        letterSpacing: 4,
        family: 'sans-serif',
        bold: true,
        shadow: true);

    final ui.Image img =
        await recorder.endRecording().toImage(width, height);
    final ByteData? data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    if (data == null) {
      throw StateError('Cover rendering produced no image data.');
    }
    return data.buffer.asUint8List();
  }

  /// Draws a generated artwork as the cover background, cropped to fill the
  /// 1600x2560 frame, then lays a soft dark wash over it so the title and
  /// author always stay readable.
  static Future<void> _paintArtwork(Canvas canvas, Uint8List art) async {
    const double w = 1600;
    const double h = 2560;
    final ui.Codec codec = await ui.instantiateImageCodec(art);
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image img = frame.image;
    try {
      final double iw = img.width.toDouble();
      final double ih = img.height.toDouble();
      final double scale = w / iw > h / ih ? w / iw : h / ih;
      final double dw = iw * scale;
      final double dh = ih * scale;
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, iw, ih),
        Rect.fromLTWH((w - dw) / 2, (h - dh) / 2, dw, dh),
        Paint()..filterQuality = FilterQuality.high,
      );
    } finally {
      img.dispose();
      codec.dispose();
    }
    // Vignette top and bottom so the typeset text has contrast to sit on.
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          const Offset(0, h),
          <Color>[
            const Color(0x66000000),
            const Color(0x22000000),
            const Color(0x33000000),
            const Color(0x99000000),
          ],
          <double>[0, 0.35, 0.7, 1],
        ),
    );
  }

  static void _drawTown(Canvas canvas, double base, CoverTheme t, int seed) {
    const double w = 1600;
    const double h = 2560;
    final Random rnd = Random(seed * 7 + 99);
    final Paint body = Paint()..color = const Color(0xFF16102B);
    final List<Rect> blocks = <Rect>[];
    double x = 0;
    while (x < w) {
      final double bw = 70 + rnd.nextInt(80).toDouble();
      final double bh = 90 + rnd.nextInt(140).toDouble();
      blocks.add(Rect.fromLTWH(x, base - bh, bw, h - (base - bh)));
      x += bw + 4 + rnd.nextInt(18);
    }
    for (final Rect r in blocks) {
      canvas.drawRect(r, body);
    }

    final Paint win = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, base - 200),
        Offset(0, base),
        <Color>[const Color(0xFFFFF6D8), t.accent],
      );
    final Random wr = Random(seed * 3 + 5);
    for (final Rect r in blocks) {
      final int rows = 1 + wr.nextInt(3);
      final int cols = max(1, r.width ~/ 55);
      for (int row = 0; row < rows; row++) {
        for (int col = 0; col < cols; col++) {
          if (wr.nextDouble() < 0.45) {
            final double wx = r.left + 14 + col * 50;
            final double wy = r.top + 24 + row * 62;
            if (wx + 22 < r.right) {
              canvas.drawRRect(
                  RRect.fromRectAndRadius(
                      Rect.fromLTWH(wx, wy, 20, 30), const Radius.circular(3)),
                  win);
            }
          }
        }
      }
    }

    // Focal building: the one that is burning / lit
    const double cx = w / 2;
    final Paint focal = Paint()..color = const Color(0xFF1A1230);
    canvas.drawRect(Rect.fromLTWH(cx - 150, base - 300, 300, 340), focal);
    final Path roof = Path()
      ..moveTo(cx, base - 400)
      ..lineTo(cx - 80, base - 290)
      ..lineTo(cx + 80, base - 290)
      ..close();
    canvas.drawPath(roof, focal);
    for (final int i in <int>[-1, 0, 1]) {
      final double ax = cx + i * 86 - 34;
      final Path arch = Path()
        ..moveTo(ax, base - 30)
        ..lineTo(ax, base - 150)
        ..arcToPoint(Offset(ax + 68, base - 150),
            radius: const Radius.circular(34))
        ..lineTo(ax + 68, base - 30)
        ..close();
      canvas.drawPath(arch, win);
    }
    canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, base + 120), width: 300, height: 380),
        Paint()
          ..color = t.accent.withValues(alpha: 0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60));
  }

  /// Draws [text] and returns the height it consumed.
  static double _text(
    Canvas canvas,
    String text,
    double top, {
    required double size,
    required Color color,
    required TextAlign align,
    String family = 'serif',
    double letterSpacing = 0,
    double height = 1.25,
    bool italic = false,
    bool bold = false,
    bool shadow = false,
  }) {
    const double pad = 110;
    const double maxWidth = 1600 - pad * 2;
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          height: height,
          letterSpacing: letterSpacing,
          fontFamily: family,
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          shadows: shadow
              ? <Shadow>[
                  const Shadow(
                      color: Color(0x99000000), blurRadius: 40, offset: Offset(0, 2))
                ]
              : null,
        ),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
      maxLines: 6,
    )..layout(maxWidth: maxWidth);
    final double dx = align == TextAlign.left ? pad : (1600 - tp.width) / 2;
    tp.paint(canvas, Offset(dx, top));
    return tp.height;
  }
}

/// Small shim so this file does not need the full material library.
const Color kWhite = Color(0xFFFFFFFF);
