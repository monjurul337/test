/// Just enough Markdown for book chapters, converted straight to XHTML.
class MarkdownToXhtml {
  static String escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String inline(String s) {
    String t = escape(s);
    t = t.replaceAllMapped(RegExp(r'\*\*\*(.+?)\*\*\*'),
        (Match m) => '<strong><em>${m[1]}</em></strong>');
    t = t.replaceAllMapped(
        RegExp(r'\*\*(.+?)\*\*'), (Match m) => '<strong>${m[1]}</strong>');
    t = t.replaceAllMapped(
        RegExp(r'(?<!\*)\*([^*]+?)\*(?!\*)'), (Match m) => '<em>${m[1]}</em>');
    t = t.replaceAllMapped(
        RegExp(r'`(.+?)`'), (Match m) => '<code>${m[1]}</code>');
    t = t.replaceAllMapped(RegExp(r'\[(.+?)\]\((https?://[^)]+)\)'),
        (Match m) => '<a href="${m[2]}">${m[1]}</a>');
    return t;
  }

  static String convert(String markdown, {required bool fiction}) {
    final List<String> lines = markdown.replaceAll('\r\n', '\n').split('\n');
    final StringBuffer out = StringBuffer();
    bool firstPara = true;
    int i = 0;

    bool isBlockStart(String l) =>
        RegExp(r'^\s*(#{1,6}\s|>\s?|([-*+]|\d+[.)])\s|\|)').hasMatch(l);

    while (i < lines.length) {
      final String line = lines[i].trimRight();
      if (line.trim().isEmpty) {
        i++;
        continue;
      }
      final String t = line.trim();

      if (t == '* * *' || t == '***') {
        out.writeln(fiction ? '<p class="brk">* * *</p>' : '<hr/>');
        firstPara = true;
        i++;
        continue;
      }
      if (t == '---') {
        out.writeln('<hr/>');
        i++;
        continue;
      }

      final RegExpMatch? h = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
      if (h != null) {
        final int level = (h[1]!.length + 1).clamp(2, 6);
        out.writeln('<h$level>${inline(h[2]!.trim())}</h$level>');
        firstPara = true;
        i++;
        continue;
      }

      if (RegExp(r'^>\s?').hasMatch(line)) {
        final List<String> buf = <String>[];
        while (i < lines.length && RegExp(r'^>\s?').hasMatch(lines[i])) {
          buf.add(lines[i].replaceFirst(RegExp(r'^>\s?'), '').trimRight());
          i++;
        }
        out.writeln('<blockquote><p>${inline(buf.join(' '))}</p></blockquote>');
        continue;
      }

      if (RegExp(r'^\s*([-*+]|\d+[.)])\s+').hasMatch(line)) {
        final bool ordered = RegExp(r'^\s*\d+[.)]\s+').hasMatch(line);
        final List<String> items = <String>[];
        while (i < lines.length &&
            RegExp(r'^\s*([-*+]|\d+[.)])\s+').hasMatch(lines[i])) {
          items.add(lines[i]
              .replaceFirst(RegExp(r'^\s*([-*+]|\d+[.)])\s+'), '')
              .trimRight());
          i++;
        }
        final String tag = ordered ? 'ol' : 'ul';
        out.write('<$tag>');
        for (final String it in items) {
          out.write('<li>${inline(it)}</li>');
        }
        out.writeln('</$tag>');
        continue;
      }

      if (t.startsWith('|') &&
          i + 1 < lines.length &&
          RegExp(r'^[\s|:-]+$').hasMatch(lines[i + 1]) &&
          lines[i + 1].contains('-')) {
        final List<List<String>> rows = <List<String>>[];
        while (i < lines.length && lines[i].trim().startsWith('|')) {
          final String row = lines[i].trim();
          rows.add(row
              .substring(1, row.endsWith('|') ? row.length - 1 : row.length)
              .split('|')
              .map((String c) => c.trim())
              .toList());
          i++;
        }
        out.write('<table><tr>');
        for (final String c in rows.first) {
          out.write('<th>${inline(c)}</th>');
        }
        out.write('</tr>');
        for (int r = 2; r < rows.length; r++) {
          out.write('<tr>');
          for (final String c in rows[r]) {
            out.write('<td>${inline(c)}</td>');
          }
          out.write('</tr>');
        }
        out.writeln('</table>');
        continue;
      }

      final List<String> buf = <String>[];
      while (i < lines.length &&
          lines[i].trim().isNotEmpty &&
          !isBlockStart(lines[i]) &&
          lines[i].trim() != '* * *' &&
          lines[i].trim() != '***' &&
          lines[i].trim() != '---') {
        buf.add(lines[i].trim());
        i++;
      }
      final String cls = fiction && firstPara ? ' class="first"' : '';
      out.writeln('<p$cls>${inline(buf.join(' '))}</p>');
      firstPara = false;
    }
    return out.toString().trim();
  }
}
