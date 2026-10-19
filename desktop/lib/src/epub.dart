import 'dart:typed_data';

import 'markdown.dart';
import 'plan.dart';
import 'zipwriter.dart';

/// Front and back matter settings: the pages a paid book is expected to have.
class BookExtras {
  const BookExtras({
    this.authorBio = '',
    this.alsoBy = const <String>[],
    this.publisher = '',
    this.contact = '',
    this.newsletter = '',
    this.storeName = 'Google Play Books',
    this.reviewCta = true,
  });

  /// Overrides the bio the planner wrote.
  final String authorBio;

  /// Your other titles, one per line in the UI.
  final List<String> alsoBy;

  final String publisher;
  final String contact;

  /// Optional "stay in touch" page: a link, a mailing list, anything.
  final String newsletter;

  /// Named in the review request at the end of the book.
  final String storeName;
  final bool reviewCta;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'authorBio': authorBio,
        'alsoBy': alsoBy,
        'publisher': publisher,
        'contact': contact,
        'newsletter': newsletter,
        'storeName': storeName,
        'reviewCta': reviewCta,
      };
}

/// Builds a validated EPUB 3 (with an EPUB 2 NCX for older readers).
class EpubBuilder {
  static const String fictionCss = '''
body{font-family:Georgia,'Times New Roman',serif;line-height:1.6;margin:0 5%;text-align:justify}
h1{font-size:1.5em;font-weight:normal;font-style:italic;text-align:center;margin:3em 0 2em;line-height:1.3}
h1 .num{display:block;font-style:normal;font-size:.62em;letter-spacing:.25em;text-transform:uppercase;opacity:.65;margin-bottom:.9em}
p{margin:0;text-indent:1.4em}
p.first{text-indent:0}
p.first::first-letter{float:left;font-size:3.1em;line-height:.82;padding:.05em .08em 0 0}
.brk{text-align:center;margin:1.6em 0;text-indent:0;letter-spacing:.6em;opacity:.65}
.tp{text-align:center;margin-top:28%}
.tp h1{font-size:2.3em;font-style:normal;margin:0 0 .4em}
.tp .sub{font-style:italic;font-size:1.15em;opacity:.85;margin-bottom:2.5em}
.tp .ser{font-size:.85em;letter-spacing:.3em;text-transform:uppercase;opacity:.7;margin-bottom:2em}
.tp .au{font-size:1.2em;letter-spacing:.12em;text-transform:uppercase}
.matter{text-align:left}
.matter h1{font-size:1.25em;font-style:normal;text-align:center;margin:2.4em 0 1.4em;letter-spacing:.06em}
.matter p{text-indent:0;margin:0 0 .9em;font-size:.95em}
.matter p.c{text-align:center}
.matter ul{margin:0 0 1em 1.2em}
.matter li{margin:0 0 .4em}
img.cover{max-width:100%;height:auto;display:block;margin:0 auto}
''';

  static const String nonfictionCss = '''
body{font-family:Georgia,serif;line-height:1.62;margin:0 5%}
h1{font-size:1.7em;line-height:1.25;margin:2.2em 0 1em;border-bottom:2px solid #ddd;padding-bottom:.35em}
h1 .num{display:block;font-size:.5em;letter-spacing:.22em;text-transform:uppercase;opacity:.6;margin-bottom:.7em;font-weight:normal}
h2{font-size:1.18em;margin:1.9em 0 .7em}
h3{font-size:1.02em;margin:1.5em 0 .5em}
p{margin:0 0 .95em}
ul,ol{margin:0 0 1em 1.3em}
li{margin-bottom:.4em}
blockquote{margin:1.2em 1.4em;padding-left:1em;border-left:3px solid #ccc;font-style:italic}
code{font-family:'Courier New',monospace;background:#f4f4f4;padding:.1em .3em;font-size:.9em}
hr{border:0;border-top:1px solid #ddd;margin:2em 0}
table{border-collapse:collapse;width:100%;margin:1.2em 0;font-size:.92em}
th,td{border:1px solid #ccc;padding:.45em .6em;text-align:left}
th{background:#f2f2f2}
.tp{text-align:center;margin-top:24%}
.tp h1{font-size:2.1em;border:0;margin:0 0 .5em}
.tp .sub{font-size:1.1em;opacity:.85;margin-bottom:2.5em;line-height:1.4}
.tp .au{font-size:1.15em;letter-spacing:.12em;text-transform:uppercase}
.matter{text-align:left}
.matter h1{font-size:1.25em;font-style:normal;text-align:center;margin:2.4em 0 1.4em;letter-spacing:.06em}
.matter p{text-indent:0;margin:0 0 .9em;font-size:.95em}
.matter p.c{text-align:center}
.matter ul{margin:0 0 1em 1.2em}
.matter li{margin:0 0 .4em}
img.cover{max-width:100%;height:auto;display:block;margin:0 auto}
''';

  static final RegExp _unnumbered = RegExp(
      r'^(Prologue|Epilogue|Introduction|Appendix|Afterword|Foreword|Preface)',
      caseSensitive: false);

  static String _page(String title, String body) =>
      '<?xml version="1.0" encoding="utf-8"?>\n'
      '<!DOCTYPE html>\n'
      '<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">\n'
      '<head><meta charset="utf-8"/><title>${MarkdownToXhtml.escape(title)}</title>'
      '<link rel="stylesheet" type="text/css" href="style.css"/></head>\n'
      '<body>\n$body\n</body></html>';

  /// Front and back matter the store expects from a paid book.
  static String _frontBack(String heading, String body) =>
      '<div class="matter"><h1>${MarkdownToXhtml.escape(heading)}</h1>$body</div>';

  /// [coverPng] is embedded as the cover image. [uuid] keeps builds reproducible.
  static Uint8List build({
    required BookPlan plan,
    required List<WrittenChapter> chapters,
    required Uint8List coverPng,
    required String uuid,
    BookExtras extras = const BookExtras(),
  }) {
    final bool fiction = plan.fiction;
    final String esc0 = MarkdownToXhtml.escape(plan.title);
    final ZipWriter z = ZipWriter();

    z.addString('mimetype', 'application/epub+zip', store: true);
    z.addString(
        'META-INF/container.xml',
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
        '<rootfiles><rootfile full-path="OEBPS/content.opf" '
        'media-type="application/oebps-package+xml"/></rootfiles></container>');

    // Title page
    final StringBuffer tp = StringBuffer('<div class="tp">');
    if (plan.series.isNotEmpty) {
      tp.write('<div class="ser">${MarkdownToXhtml.escape(plan.series)}</div>');
    }
    tp.write('<h1>$esc0</h1>');
    if (plan.subtitle.isNotEmpty) {
      tp.write('<div class="sub">${MarkdownToXhtml.escape(plan.subtitle)}</div>');
    }
    tp.write('<div class="au">${MarkdownToXhtml.escape(plan.author)}</div></div>');

    final int year = DateTime.now().year;
    final String holder = extras.publisher.isEmpty ? plan.author : extras.publisher;
    final StringBuffer cp = StringBuffer()
      ..write('<p class="c">${MarkdownToXhtml.escape(plan.title)}</p>')
      ..write('<p class="c">Copyright &#169; $year '
          '${MarkdownToXhtml.escape(plan.author)}</p>')
      ..write('<p>All rights reserved. No part of this book may be reproduced '
          'or transmitted in any form without written permission from the '
          'author, except for brief quotations in a review.</p>');
    if (fiction) {
      cp.write('<p>This is a work of fiction. Names, characters, places and '
          'incidents are products of the author&#8217;s imagination or are '
          'used fictitiously. Any resemblance to real persons, living or '
          'dead, events or locales is entirely coincidental.</p>');
    }
    cp
      ..write('<p>Published by ${MarkdownToXhtml.escape(holder)}</p>')
      ..write('<p>First edition, $year</p>')
      ..write('<p>Cover design by ${MarkdownToXhtml.escape(plan.author)}</p>');
    if (extras.contact.isNotEmpty) {
      cp.write('<p>${MarkdownToXhtml.escape(extras.contact)}</p>');
    }

    final List<List<String>> docs = <List<String>>[
      <String>['titlepage.xhtml', 'Title Page', _page(plan.title, tp.toString())],
      <String>[
        'copyright.xhtml',
        'Copyright',
        _page('Copyright', _frontBack('Copyright', cp.toString())),
      ],
    ];

    for (int i = 0; i < chapters.length; i++) {
      final WrittenChapter c = chapters[i];
      final String clean =
          c.title.replaceFirst(RegExp(r'^Chapter\s+\d+[:.]?\s*', caseSensitive: false), '');
      final String num = _unnumbered.hasMatch(c.title)
          ? ''
          : '<span class="num">Chapter ${i + 1}</span>';
      final String html =
          '<h1>$num${MarkdownToXhtml.escape(clean)}</h1>\n'
          '${MarkdownToXhtml.convert(c.body, fiction: fiction)}';
      docs.add(<String>[
        'ch${(i + 1).toString().padLeft(2, '0')}.xhtml',
        c.title,
        _page(c.title, html),
      ]);
    }

    // ---- Back matter ----
    if (extras.reviewCta) {
      final String where = extras.storeName.isEmpty
          ? 'the store you bought it from'
          : extras.storeName;
      docs.add(<String>[
        'thanks.xhtml',
        'Enjoyed this book?',
        _page(
          'Enjoyed this book?',
          _frontBack(
            'Enjoyed this book?',
            '<p>Thank you for reading '
                '<em>${MarkdownToXhtml.escape(plan.title)}</em>.</p>'
                '<p>Independent books live and die by their reviews. If this '
                'one was worth your time, a short, honest rating on '
                '${MarkdownToXhtml.escape(where)} helps more than you would '
                'think - it is what puts the book in front of the next '
                'reader.</p>'
                '<p class="c">Thank you.</p>',
          ),
        ),
      ]);
    }

    final String bio =
        extras.authorBio.isNotEmpty ? extras.authorBio : plan.authorBio;
    if (bio.isNotEmpty) {
      docs.add(<String>[
        'author.xhtml',
        'About the author',
        _page(
          'About the author',
          _frontBack('About the author',
              MarkdownToXhtml.convert(bio, fiction: false)),
        ),
      ]);
    }

    if (extras.alsoBy.isNotEmpty) {
      final StringBuffer ab = StringBuffer('<ul>');
      for (final String t in extras.alsoBy) {
        ab.write('<li>${MarkdownToXhtml.escape(t)}</li>');
      }
      ab.write('</ul>');
      docs.add(<String>[
        'alsoby.xhtml',
        'Also by ${plan.author}',
        _page(
          'Also by ${plan.author}',
          _frontBack('Also by ${plan.author}', ab.toString()),
        ),
      ]);
    }

    if (extras.newsletter.isNotEmpty) {
      docs.add(<String>[
        'newsletter.xhtml',
        'Stay in touch',
        _page(
          'Stay in touch',
          _frontBack('Stay in touch',
              MarkdownToXhtml.convert(extras.newsletter, fiction: false)),
        ),
      ]);
    }

    // Where the reader should land: the first chapter, not the front matter.
    final String bodyStart = docs
        .map((List<String> d) => d[0])
        .firstWhere((String f) => f.startsWith('ch'),
            orElse: () => docs.first[0]);

    // Navigation
    final StringBuffer nav = StringBuffer(
        '<nav epub:type="toc" id="toc"><h1>Contents</h1><ol>');
    final StringBuffer ncx = StringBuffer(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">\n'
        '<head><meta name="dtb:uid" content="urn:uuid:$uuid"/></head>'
        '<docTitle><text>$esc0</text></docTitle><navMap>');
    for (int i = 1; i < docs.length; i++) {
      final String file = docs[i][0];
      final String label = MarkdownToXhtml.escape(docs[i][1]);
      nav.write('<li><a href="$file">$label</a></li>');
      ncx.write('<navPoint id="n$i" playOrder="$i"><navLabel><text>$label</text>'
          '</navLabel><content src="$file"/></navPoint>');
    }
    nav.write('</ol></nav>');

    // Google Play Books starts the free sample at the EPUB 3 "bodymatter"
    // landmark, so the preview opens on chapter 1 instead of the copyright
    // page. See support.google.com/books/partner/answer/3316879.
    nav.write('<nav epub:type="landmarks" id="landmarks" hidden="hidden">'
        '<h1>Guide</h1><ol>'
        '<li><a epub:type="cover" href="coverpage.xhtml">Cover</a></li>'
        '<li><a epub:type="toc" href="nav.xhtml">Contents</a></li>'
        '<li><a epub:type="bodymatter" href="$bodyStart">Start of content</a>'
        '</li></ol></nav>');

    ncx.write('</navMap></ncx>');

    z.addString(
        'OEBPS/nav.xhtml',
        '<?xml version="1.0" encoding="utf-8"?>\n<!DOCTYPE html>\n'
        '<html xmlns="http://www.w3.org/1999/xhtml" '
        'xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="en" lang="en">\n'
        '<head><meta charset="utf-8"/><title>Contents</title>'
        '<link rel="stylesheet" type="text/css" href="style.css"/></head>\n'
        '<body>$nav</body></html>');
    z.addString('OEBPS/toc.ncx', ncx.toString());
    z.addString('OEBPS/style.css', fiction ? fictionCss : nonfictionCss);
    z.addBytes('OEBPS/cover.png', coverPng);
    z.addString(
        'OEBPS/coverpage.xhtml',
        _page(plan.title,
            '<div style="text-align:center"><img class="cover" src="cover.png" alt="Cover"/></div>'));

    final String now = DateTime.now().toUtc().toIso8601String().split('.').first;
    final String fullTitle =
        plan.subtitle.isEmpty ? plan.title : '${plan.title}: ${plan.subtitle}';
    final StringBuffer opf = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="utf-8"?>')
      ..writeln('<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
          'unique-identifier="bid">')
      ..writeln('<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">')
      ..writeln('<dc:identifier id="bid">urn:uuid:$uuid</dc:identifier>')
      ..writeln('<dc:title>${MarkdownToXhtml.escape(fullTitle)}</dc:title>')
      ..writeln('<dc:creator>${MarkdownToXhtml.escape(plan.author)}</dc:creator>')
      ..writeln('<dc:language>en</dc:language>')
      ..writeln('<dc:date>${now.split('T').first}</dc:date>')
      ..writeln('<meta property="dcterms:modified">${now}Z</meta>')
      ..writeln('<meta name="cover" content="coverimg"/>');
    if (extras.publisher.isNotEmpty) {
      opf.writeln(
          '<dc:publisher>${MarkdownToXhtml.escape(extras.publisher)}</dc:publisher>');
    }
    if (plan.description.isNotEmpty) {
      opf.writeln(
          '<dc:description>${MarkdownToXhtml.escape(plan.description)}</dc:description>');
    }
    for (final String k in plan.keywords) {
      opf.writeln('<dc:subject>${MarkdownToXhtml.escape(k)}</dc:subject>');
    }
    opf
      ..writeln('</metadata><manifest>')
      ..writeln('<item id="nav" href="nav.xhtml" '
          'media-type="application/xhtml+xml" properties="nav"/>')
      ..writeln('<item id="ncx" href="toc.ncx" '
          'media-type="application/x-dtbncx+xml"/>')
      ..writeln('<item id="css" href="style.css" media-type="text/css"/>')
      ..writeln('<item id="coverimg" href="cover.png" media-type="image/png" '
          'properties="cover-image"/>')
      ..writeln('<item id="coverpage" href="coverpage.xhtml" '
          'media-type="application/xhtml+xml"/>');
    for (final List<String> d in docs) {
      opf.writeln('<item id="${_id(d[0])}" href="${d[0]}" '
          'media-type="application/xhtml+xml"/>');
    }
    opf
      ..writeln('</manifest><spine toc="ncx">')
      ..writeln('<itemref idref="coverpage"/>');
    for (final List<String> d in docs) {
      opf.writeln('<itemref idref="${_id(d[0])}"/>');
    }
    opf
      ..writeln('<itemref idref="nav"/>')
      ..writeln('</spine></package>');

    z.addString('OEBPS/content.opf', opf.toString());
    for (final List<String> d in docs) {
      z.addString('OEBPS/${d[0]}', d[2]);
    }
    return z.finish();
  }

  static String _id(String file) => file.replaceAll('.', '_');
}
