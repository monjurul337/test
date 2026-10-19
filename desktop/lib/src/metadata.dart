import 'plan.dart';

/// One row of the upload form.
class PublishField {
  const PublishField(this.group, this.label, this.value, {this.hint = ''});

  final String group;
  final String label;
  final String value;
  final String hint;
}

/// Single source of truth for everything a storefront asks for. The on-screen
/// checklist and metadata.txt are both generated from this list, so they can
/// never drift apart.
class PublishFields {
  static String two(int n) => n.toString().padLeft(2, '0');

  static String date(DateTime d) =>
      '${d.year}-${two(d.month)}-${two(d.day)}';

  static int pages(int words) => (words / 250).round();

  static List<PublishField> build({
    required BookPlan plan,
    required int words,
    required int chapterCount,
    required String epubName,
    DateTime? today,
  }) {
    final DateTime now = today ?? DateTime.now();
    final DateTime release = now.add(const Duration(days: 10));
    final List<PublishField> f = <PublishField>[];

    void add(String group, String label, String value, [String hint = '']) {
      if (value.trim().isEmpty) return;
      f.add(PublishField(group, label, value, hint: hint));
    }

    // 1 - Files
    add('Files', 'Book file', epubName,
        'Validated EPUB 3. Upload this as the book content.');
    add('Files', 'Cover image', 'cover.png',
        '1600 x 2560. Upload separately - the cover embedded in the EPUB is not enough for Google Play.');

    // 2 - Store listing
    add('Store listing', 'Title', plan.title);
    add('Store listing', 'Subtitle', plan.subtitle);
    add('Store listing', 'Series', plan.series,
        'Series name and number. Leave blank if the book is standalone.');
    add('Store listing', 'Contributor', plan.author, 'Role: Author');
    add('Store listing', 'Contributor biography', plan.authorBio);
    add('Store listing', 'Short description', plan.shortDescription,
        'Under 400 characters, for stores with a short field.');
    add('Store listing', 'Description', plan.description,
        'The main store blurb.');
    for (int i = 0; i < plan.bisac.length; i++) {
      add('Store listing', 'Genre / BISAC ${i + 1}', plan.bisac[i],
          i == 0 ? 'The first one is treated as the primary category.' : '');
    }
    if (plan.keywords.isNotEmpty) {
      add('Store listing', 'Keywords', plan.keywords.join(', '),
          'Use every slot the form gives you.');
    }
    add('Store listing', 'Language', 'English (en)');

    // 3 - Pricing and rights
    add('Pricing and rights', 'List price',
        'USD ${plan.priceUsd.toStringAsFixed(2)}',
        'Below USD 2.99 Amazon pays 35% instead of 70%.');
    add('Pricing and rights', 'ISBN', 'Leave blank',
        'Google Play assigns a free identifier at upload, so you do not need one.');
    add('Pricing and rights', 'Territories', 'Worldwide');

    // 4 - Audience
    add('Audience', 'Minimum age', '${plan.minAge}');
    add('Audience', 'Maximum age', 'Leave blank',
        'Setting a maximum caps your audience for no benefit.');
    add('Audience', 'For mature audiences?', plan.mature ? 'Yes' : 'No',
        plan.mature
            ? 'This book contains adult content, so the flag is required.'
            : 'Saying Yes without cause removes the book from recommendations in many countries.');

    // 5 - Dates
    add('Dates', 'Publication date', date(now),
        'The day the book is first published - today.');
    add('Dates', 'Release date', date(release),
        'About 10 days out, so every store goes live together. Distribution takes 3-7 days.');
    add('Dates', 'Allow pre-orders?', 'No',
        'Yes only for book 2 or later in a series, once you already have readers.');

    // 6 - Content protection
    add('Content protection', 'Apply DRM encryption?', 'No',
        'DRM does not stop piracy and annoys real buyers. DRM-free is the indie standard.');
    add('Content protection', 'Preview limit', '20%',
        'In fiction the preview is the sales pitch. Do not lower it.');
    add('Content protection', 'Copy / paste limit', '0%',
        'A small allowance lets reviewers quote you, but 0% is fine.');

    // 7 - Book details
    add('Book details', 'Page count', '${pages(words)}',
        'EPUB has no fixed pages; stores use this only as a hint.');
    add('Book details', 'Word count', '$words');
    add('Book details', 'Chapters', '$chapterCount');
    add('Book details', 'Target reader', plan.targetReader);
    if (plan.compTitles.isNotEmpty) {
      add('Book details', 'Comparable titles', plan.compTitles.join('; '),
          'Useful for ads and for picking categories.');
    }

    return f;
  }

  static const List<String> groups = <String>[
    'Files',
    'Store listing',
    'Pricing and rights',
    'Audience',
    'Dates',
    'Content protection',
    'Book details',
  ];

  /// The ordered things a first-time publisher still has to do by hand.
  static const List<String> steps = <String>[
    'Sign in to Google Play Books Partner Center and open Book catalog.',
    'Add a new book, upload the EPUB, then upload cover.png separately.',
    'Paste the store listing fields below, in order.',
    'Set the price, age range, DRM and preview limits exactly as listed.',
    'Set the publication and release dates, leave pre-orders off.',
    'Accept the distribution terms yourself - no tool can do that for you.',
    'Submit, then check back in 3-7 days; "Needs action" means a required field is still empty.',
  ];
}

/// The plain-text upload sheet that ships next to the EPUB.
class MetadataSheet {
  static String build({
    required BookPlan plan,
    required int words,
    required int chapterCount,
    required String epubName,
    DateTime? today,
  }) {
    final List<PublishField> fields = PublishFields.build(
      plan: plan,
      words: words,
      chapterCount: chapterCount,
      epubName: epubName,
      today: today,
    );
    final StringBuffer b = StringBuffer()
      ..writeln('=' * 70)
      ..writeln('BOOK METADATA - ${plan.title}')
      ..writeln('Generated by Book Generator - Meta Hawladar Team')
      ..writeln('=' * 70)
      ..writeln()
      ..writeln('WHAT YOU STILL HAVE TO DO')
      ..writeln('-' * 70);
    for (int i = 0; i < PublishFields.steps.length; i++) {
      b.writeln('${i + 1}. ${_wrap(PublishFields.steps[i], 66, '   ')}');
    }
    b.writeln();

    for (final String group in PublishFields.groups) {
      final List<PublishField> rows =
          fields.where((PublishField x) => x.group == group).toList();
      if (rows.isEmpty) continue;
      b
        ..writeln('=' * 70)
        ..writeln(group.toUpperCase())
        ..writeln('=' * 70)
        ..writeln();
      for (final PublishField r in rows) {
        b
          ..writeln('-' * 70)
          ..writeln(r.label.toUpperCase())
          ..writeln(_wrap(r.value, 70));
        if (r.hint.isNotEmpty) {
          b.writeln(_wrap('  why: ${r.hint}', 70, '       '));
        }
        b.writeln();
      }
    }
    b.writeln('=' * 70);
    return b.toString();
  }

  static String _wrap(String text, [int width = 78, String indent = '']) {
    final List<String> out = <String>[];
    for (final String para in text.split('\n')) {
      if (para.trim().isEmpty) {
        out.add('');
        continue;
      }
      final StringBuffer line = StringBuffer();
      for (final String word in para.trim().split(RegExp(r'\s+'))) {
        if (line.isEmpty) {
          line.write(word);
        } else if (line.length + 1 + word.length <= width) {
          line.write(' $word');
        } else {
          out.add(line.toString());
          line
            ..clear()
            ..write(word);
        }
      }
      if (line.isNotEmpty) out.add(line.toString());
    }
    return out.length <= 1 ? out.join() : out.first + '\n' + out.skip(1).map((String l) => '$indent$l').join('\n');
  }
}
