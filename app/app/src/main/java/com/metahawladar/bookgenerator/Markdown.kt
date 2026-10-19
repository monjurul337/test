package com.metahawladar.bookgenerator

/** Just enough Markdown for book chapters, converted straight to XHTML. */
object Markdown {

    fun escape(s: String): String = s
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\"", "&quot;")

    fun inline(s: String): String {
        var t = escape(s)
        t = Regex("\\*\\*\\*(.+?)\\*\\*\\*").replace(t) { "<strong><em>${it.groupValues[1]}</em></strong>" }
        t = Regex("\\*\\*(.+?)\\*\\*").replace(t) { "<strong>${it.groupValues[1]}</strong>" }
        t = Regex("(?<!\\*)\\*([^*]+?)\\*(?!\\*)").replace(t) { "<em>${it.groupValues[1]}</em>" }
        t = Regex("`(.+?)`").replace(t) { "<code>${it.groupValues[1]}</code>" }
        t = Regex("\\[(.+?)]\\((https?://[^)]+)\\)").replace(t) {
            "<a href=\"${it.groupValues[2]}\">${it.groupValues[1]}</a>"
        }
        return t
    }

    private val BLOCK_START = Regex("^\\s*(#{1,6}\\s|>\\s?|([-*+]|\\d+[.)])\\s|\\|)")
    private val HEADING = Regex("^(#{1,6})\\s+(.*)$")
    private val QUOTE = Regex("^>\\s?")
    private val LIST = Regex("^\\s*([-*+]|\\d+[.)])\\s+")
    private val ORDERED = Regex("^\\s*\\d+[.)]\\s+")

    fun toXhtml(markdown: String, fiction: Boolean): String {
        val lines = markdown.replace("\r\n", "\n").split("\n")
        val out = StringBuilder()
        var firstPara = true
        var i = 0

        fun isBreak(t: String) = t == "* * *" || t == "***"

        while (i < lines.size) {
            val line = lines[i].trimEnd()
            val t = line.trim()
            if (t.isEmpty()) { i++; continue }

            if (isBreak(t)) {
                out.append(if (fiction) "<p class=\"brk\">* * *</p>\n" else "<hr/>\n")
                firstPara = true; i++; continue
            }
            if (t == "---") { out.append("<hr/>\n"); i++; continue }

            val h = HEADING.find(line)
            if (h != null) {
                val level = (h.groupValues[1].length + 1).coerceIn(2, 6)
                out.append("<h$level>${inline(h.groupValues[2].trim())}</h$level>\n")
                firstPara = true; i++; continue
            }

            if (QUOTE.containsMatchIn(line)) {
                val buf = ArrayList<String>()
                while (i < lines.size && QUOTE.containsMatchIn(lines[i])) {
                    buf.add(lines[i].replaceFirst(QUOTE, "").trimEnd()); i++
                }
                out.append("<blockquote><p>${inline(buf.joinToString(" "))}</p></blockquote>\n")
                continue
            }

            if (LIST.containsMatchIn(line)) {
                val ordered = ORDERED.containsMatchIn(line)
                val items = ArrayList<String>()
                while (i < lines.size && LIST.containsMatchIn(lines[i])) {
                    items.add(lines[i].replaceFirst(LIST, "").trimEnd()); i++
                }
                val tag = if (ordered) "ol" else "ul"
                out.append("<$tag>")
                items.forEach { out.append("<li>${inline(it)}</li>") }
                out.append("</$tag>\n")
                continue
            }

            if (t.startsWith("|") && i + 1 < lines.size &&
                lines[i + 1].contains("-") &&
                Regex("^[\\s|:-]+$").matches(lines[i + 1])
            ) {
                val rows = ArrayList<List<String>>()
                while (i < lines.size && lines[i].trim().startsWith("|")) {
                    val row = lines[i].trim().trim('|')
                    rows.add(row.split("|").map { it.trim() })
                    i++
                }
                out.append("<table><tr>")
                rows.first().forEach { out.append("<th>${inline(it)}</th>") }
                out.append("</tr>")
                for (r in 2 until rows.size) {
                    out.append("<tr>")
                    rows[r].forEach { out.append("<td>${inline(it)}</td>") }
                    out.append("</tr>")
                }
                out.append("</table>\n")
                continue
            }

            val buf = ArrayList<String>()
            while (i < lines.size) {
                val cur = lines[i]
                if (cur.trim().isEmpty() || BLOCK_START.containsMatchIn(cur) ||
                    isBreak(cur.trim()) || cur.trim() == "---"
                ) break
                buf.add(cur.trim()); i++
            }
            val cls = if (fiction && firstPara) " class=\"first\"" else ""
            out.append("<p$cls>${inline(buf.joinToString(" "))}</p>\n")
            firstPara = false
        }
        return out.toString().trim()
    }
}
