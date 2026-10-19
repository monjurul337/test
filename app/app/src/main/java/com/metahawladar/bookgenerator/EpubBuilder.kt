package com.metahawladar.bookgenerator

import java.io.File
import java.util.UUID
import java.util.zip.CRC32
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/** Builds a validated EPUB 3 (with an EPUB 2 NCX for older readers). */

/** Front and back matter settings: the pages a paid book is expected to have. */
data class BookExtras(
    val authorBio: String = "",
    val alsoBy: List<String> = emptyList(),
    val publisher: String = "",
    val contact: String = "",
    val newsletter: String = "",
    val storeName: String = "Google Play Books",
    val reviewCta: Boolean = true,
)

object EpubBuilder {

    private const val FICTION_CSS = """
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
"""

    private const val NONFICTION_CSS = """
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
"""

    private val UNNUMBERED = Regex(
        "^(Prologue|Epilogue|Introduction|Appendix|Afterword|Foreword|Preface)",
        RegexOption.IGNORE_CASE,
    )

    private fun matter(heading: String, body: String): String =
        "<div class=\"matter\"><h1>${Markdown.escape(heading)}</h1>$body</div>"

    private fun page(title: String, body: String): String =
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<!DOCTYPE html>\n" +
            "<html xmlns=\"http://www.w3.org/1999/xhtml\" xml:lang=\"en\" lang=\"en\">\n" +
            "<head><meta charset=\"utf-8\"/><title>${Markdown.escape(title)}</title>" +
            "<link rel=\"stylesheet\" type=\"text/css\" href=\"style.css\"/></head>\n" +
            "<body>\n$body\n</body></html>"

    fun build(
        plan: BookPlan,
        chapters: List<WrittenChapter>,
        coverPng: ByteArray,
        target: File,
        extras: BookExtras = BookExtras(),
    ) {
        val uuid = UUID.randomUUID().toString()
        val fiction = plan.fiction
        val escTitle = Markdown.escape(plan.title)

        val tp = StringBuilder("<div class=\"tp\">")
        if (plan.series.isNotEmpty()) tp.append("<div class=\"ser\">${Markdown.escape(plan.series)}</div>")
        tp.append("<h1>$escTitle</h1>")
        if (plan.subtitle.isNotEmpty()) tp.append("<div class=\"sub\">${Markdown.escape(plan.subtitle)}</div>")
        tp.append("<div class=\"au\">${Markdown.escape(plan.author)}</div></div>")

        data class Doc(val file: String, val label: String, val html: String)

        val docs = ArrayList<Doc>()
        docs.add(Doc("titlepage.xhtml", "Title Page", page(plan.title, tp.toString())))

        val year = java.util.Calendar.getInstance().get(java.util.Calendar.YEAR)
        val holder = extras.publisher.ifBlank { plan.author }
        val cp = StringBuilder()
            .append("<p class=\"c\">${Markdown.escape(plan.title)}</p>")
            .append("<p class=\"c\">Copyright &#169; $year ${Markdown.escape(plan.author)}</p>")
            .append(
                "<p>All rights reserved. No part of this book may be reproduced " +
                    "or transmitted in any form without written permission from the " +
                    "author, except for brief quotations in a review.</p>"
            )
        if (fiction) {
            cp.append(
                "<p>This is a work of fiction. Names, characters, places and " +
                    "incidents are products of the author&#8217;s imagination or are " +
                    "used fictitiously. Any resemblance to real persons, living or " +
                    "dead, events or locales is entirely coincidental.</p>"
            )
        }
        cp.append("<p>Published by ${Markdown.escape(holder)}</p>")
            .append("<p>First edition, $year</p>")
            .append("<p>Cover design by ${Markdown.escape(plan.author)}</p>")
        if (extras.contact.isNotBlank()) {
            cp.append("<p>${Markdown.escape(extras.contact)}</p>")
        }
        docs.add(Doc("copyright.xhtml", "Copyright", page("Copyright", matter("Copyright", cp.toString()))))

        chapters.forEachIndexed { i, c ->
            val clean = c.title.replace(Regex("^Chapter\\s+\\d+[:.]?\\s*", RegexOption.IGNORE_CASE), "")
            val num = if (UNNUMBERED.containsMatchIn(c.title)) {
                ""
            } else {
                "<span class=\"num\">Chapter ${i + 1}</span>"
            }
            val html = "<h1>$num${Markdown.escape(clean)}</h1>\n" +
                Markdown.toXhtml(c.body, fiction)
            docs.add(Doc("ch%02d.xhtml".format(i + 1), c.title, page(c.title, html)))
        }

        // ---- Back matter ----
        if (extras.reviewCta) {
            val where = extras.storeName.ifBlank { "the store you bought it from" }
            docs.add(
                Doc(
                    "thanks.xhtml", "Enjoyed this book?",
                    page(
                        "Enjoyed this book?",
                        matter(
                            "Enjoyed this book?",
                            "<p>Thank you for reading <em>${Markdown.escape(plan.title)}</em>.</p>" +
                                "<p>Independent books live and die by their reviews. If this " +
                                "one was worth your time, a short, honest rating on " +
                                "${Markdown.escape(where)} helps more than you would think - " +
                                "it is what puts the book in front of the next reader.</p>" +
                                "<p class=\"c\">Thank you.</p>"
                        )
                    )
                )
            )
        }
        val bio = extras.authorBio.ifBlank { plan.authorBio }
        if (bio.isNotBlank()) {
            docs.add(
                Doc(
                    "author.xhtml", "About the author",
                    page("About the author", matter("About the author", Markdown.toXhtml(bio, false)))
                )
            )
        }
        if (extras.alsoBy.isNotEmpty()) {
            val ab = StringBuilder("<ul>")
            extras.alsoBy.forEach { ab.append("<li>${Markdown.escape(it)}</li>") }
            ab.append("</ul>")
            docs.add(
                Doc(
                    "alsoby.xhtml", "Also by ${plan.author}",
                    page("Also by ${plan.author}", matter("Also by ${plan.author}", ab.toString()))
                )
            )
        }
        if (extras.newsletter.isNotBlank()) {
            docs.add(
                Doc(
                    "newsletter.xhtml", "Stay in touch",
                    page("Stay in touch", matter("Stay in touch", Markdown.toXhtml(extras.newsletter, false)))
                )
            )
        }

        val nav = StringBuilder("<nav epub:type=\"toc\" id=\"toc\"><h1>Contents</h1><ol>")
        val ncx = StringBuilder(
            "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n" +
                "<ncx xmlns=\"http://www.daisy.org/z3986/2005/ncx/\" version=\"2005-1\">\n" +
                "<head><meta name=\"dtb:uid\" content=\"urn:uuid:$uuid\"/></head>" +
                "<docTitle><text>$escTitle</text></docTitle><navMap>"
        )
        for (i in 1 until docs.size) {
            val label = Markdown.escape(docs[i].label)
            nav.append("<li><a href=\"${docs[i].file}\">$label</a></li>")
            ncx.append(
                "<navPoint id=\"n$i\" playOrder=\"$i\"><navLabel><text>$label</text>" +
                    "</navLabel><content src=\"${docs[i].file}\"/></navPoint>"
            )
        }
        nav.append("</ol></nav>")
        ncx.append("</navMap></ncx>")

        val now = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", java.util.Locale.US).apply {
            timeZone = java.util.TimeZone.getTimeZone("UTC")
        }.format(java.util.Date())

        val fullTitle = if (plan.subtitle.isEmpty()) plan.title else "${plan.title}: ${plan.subtitle}"
        val opf = StringBuilder()
            .appendLine("<?xml version=\"1.0\" encoding=\"utf-8\"?>")
            .appendLine("<package xmlns=\"http://www.idpf.org/2007/opf\" version=\"3.0\" unique-identifier=\"bid\">")
            .appendLine("<metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">")
            .appendLine("<dc:identifier id=\"bid\">urn:uuid:$uuid</dc:identifier>")
            .appendLine("<dc:title>${Markdown.escape(fullTitle)}</dc:title>")
            .appendLine("<dc:creator>${Markdown.escape(plan.author)}</dc:creator>")
            .appendLine("<dc:language>en</dc:language>")
            .appendLine("<dc:date>${now.substring(0, 10)}</dc:date>")
            .appendLine("<meta property=\"dcterms:modified\">$now</meta>")
            .appendLine("<meta name=\"cover\" content=\"coverimg\"/>")
        if (plan.description.isNotEmpty()) {
            opf.appendLine("<dc:description>${Markdown.escape(plan.description)}</dc:description>")
        }
        plan.keywords.forEach { opf.appendLine("<dc:subject>${Markdown.escape(it)}</dc:subject>") }
        opf.appendLine("</metadata><manifest>")
            .appendLine("<item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>")
            .appendLine("<item id=\"ncx\" href=\"toc.ncx\" media-type=\"application/x-dtbncx+xml\"/>")
            .appendLine("<item id=\"css\" href=\"style.css\" media-type=\"text/css\"/>")
            .appendLine("<item id=\"coverimg\" href=\"cover.png\" media-type=\"image/png\" properties=\"cover-image\"/>")
            .appendLine("<item id=\"coverpage\" href=\"coverpage.xhtml\" media-type=\"application/xhtml+xml\"/>")
        docs.forEach {
            opf.appendLine(
                "<item id=\"${it.file.replace(".", "_")}\" href=\"${it.file}\" " +
                    "media-type=\"application/xhtml+xml\"/>"
            )
        }
        opf.appendLine("</manifest><spine toc=\"ncx\">")
            .appendLine("<itemref idref=\"coverpage\"/>")
        docs.forEach { opf.appendLine("<itemref idref=\"${it.file.replace(".", "_")}\"/>") }
        opf.appendLine("<itemref idref=\"nav\"/>").appendLine("</spine></package>")

        ZipOutputStream(target.outputStream().buffered()).use { zip ->
            // "mimetype" must be the first entry and stored uncompressed.
            val mimetype = "application/epub+zip".toByteArray(Charsets.UTF_8)
            zip.setLevel(0)
            val entry = ZipEntry("mimetype").apply {
                method = ZipEntry.STORED
                size = mimetype.size.toLong()
                compressedSize = mimetype.size.toLong()
                crc = CRC32().apply { update(mimetype) }.value
            }
            zip.putNextEntry(entry)
            zip.write(mimetype)
            zip.closeEntry()
            zip.setLevel(9)

            fun put(name: String, bytes: ByteArray) {
                zip.putNextEntry(ZipEntry(name).apply { method = ZipEntry.DEFLATED })
                zip.write(bytes)
                zip.closeEntry()
            }
            fun putText(name: String, text: String) = put(name, text.toByteArray(Charsets.UTF_8))

            putText(
                "META-INF/container.xml",
                "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n" +
                    "<container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\">" +
                    "<rootfiles><rootfile full-path=\"OEBPS/content.opf\" " +
                    "media-type=\"application/oebps-package+xml\"/></rootfiles></container>"
            )
            putText(
                "OEBPS/nav.xhtml",
                "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<!DOCTYPE html>\n" +
                    "<html xmlns=\"http://www.w3.org/1999/xhtml\" " +
                    "xmlns:epub=\"http://www.idpf.org/2007/ops\" xml:lang=\"en\" lang=\"en\">\n" +
                    "<head><meta charset=\"utf-8\"/><title>Contents</title>" +
                    "<link rel=\"stylesheet\" type=\"text/css\" href=\"style.css\"/></head>\n" +
                    "<body>$nav</body></html>"
            )
            putText("OEBPS/toc.ncx", ncx.toString())
            putText("OEBPS/style.css", if (fiction) FICTION_CSS else NONFICTION_CSS)
            put("OEBPS/cover.png", coverPng)
            putText(
                "OEBPS/coverpage.xhtml",
                page(
                    plan.title,
                    "<div style=\"text-align:center\">" +
                        "<img class=\"cover\" src=\"cover.png\" alt=\"Cover\"/></div>"
                )
            )
            putText("OEBPS/content.opf", opf.toString())
            docs.forEach { putText("OEBPS/${it.file}", it.html) }
        }
    }

    /** Used by the UI to show the finished size without re-reading the file. */
    fun sizeOf(file: File): String {
        val kb = file.length() / 1024.0
        return if (kb < 1024) "%.0f KB".format(kb) else "%.1f MB".format(kb / 1024)
    }
}
