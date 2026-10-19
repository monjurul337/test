import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'plan.dart';

/// Strips light Markdown so prose reads cleanly in the PDF too.
List<String> pdfParagraphs(String body) {
  final List<String> out = <String>[];
  for (String line in body.split('\n')) {
    line = line.trim().replaceAll('**', '').replaceAll('~~', '');
    if (line.isEmpty) continue;
    if (RegExp(r'^---+$').hasMatch(line)) {
      out.add('* * *');
      continue;
    }
    out.add(line);
  }
  return out;
}

/// Builds a clean PDF edition of the finished book: a title page plus every
/// chapter in order, one column, generous margins. Emitted alongside the
/// EPUB on every run.
class PdfBuilder {
  static Future<Uint8List> build(
    BookPlan plan,
    List<WrittenChapter> chapters,
  ) async {
    final pw.Document doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(72, 200, 72, 72),
        build: (pw.Context ctx) => pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.start,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: <pw.Widget>[
            if (plan.series.isNotEmpty) ...<pw.Widget>[
              pw.Text(plan.series.toUpperCase(),
                  style: const pw.TextStyle(
                      fontSize: 10, letterSpacing: 3, color: PdfColors.grey700)),
              pw.SizedBox(height: 18),
            ],
            pw.Text(plan.title,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                    fontSize: plan.title.length < 40 ? 34 : 26,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black)),
            if (plan.subtitle.isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 14),
                child: pw.Text(plan.subtitle,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                        fontSize: 15,
                        fontStyle: pw.FontStyle.italic,
                        color: PdfColors.grey800)),
              ),
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 44),
              child: pw.Text(plan.author.toUpperCase(),
                  style: pw.TextStyle(
                      fontSize: 13,
                      letterSpacing: 2.4,
                      color: PdfColors.black)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 120),
              child: pw.Text(plan.tagline.isEmpty ? '' : plan.tagline,
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(
                      fontSize: 12, fontStyle: pw.FontStyle.italic,
                      color: PdfColors.grey600)),
            ),
          ],
        ),
      ),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 72, vertical: 64),
        footer: (pw.Context ctx) => pw.Center(
          child: pw.Text('${ctx.pageNumber}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
        ),
        build: (pw.Context ctx) {
          final List<pw.Widget> blocks = <pw.Widget>[];
          for (int i = 0; i < chapters.length; i++) {
            final WrittenChapter ch = chapters[i];
            blocks.add(pw.Header(
              padding: const pw.EdgeInsets.only(top: 20, bottom: 18),
              child: pw.Text(
                chapters.length > 1 ? '${i + 1}. ${ch.title}' : ch.title,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 17,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                ),
              ),
            ));
            final List<String> paras = pdfParagraphs(ch.body);
            for (int j = 0; j < paras.length; j++) {
              final bool divider = paras[j].startsWith('* * *');
              blocks.add(
                pw.Padding(
                  padding: pw.EdgeInsets.only(bottom: divider ? 20 : 11),
                  child: pw.Text(
                    paras[j],
                    textAlign: pw.TextAlign.justify,
                    style: pw.TextStyle(
                      fontSize: 11.4,
                      lineHeight: 1.6,
                      color: PdfColors.black,
                    ),
                  ),
                ),
              );
            }
            blocks.add(pw.SizedBox(height: 18));
          }
          return blocks;
        },
      ),
    );

    return doc.save();
  }
}
