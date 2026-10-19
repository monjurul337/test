package com.metahawladar.bookgenerator

import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import java.io.ByteArrayOutputStream

/**
 * Builds a clean PDF edition of the finished book: a title page plus every
 * chapter in order, one column, generous margins. Emitted alongside the
 * EPUB on every run.
 */
object PdfBuilder {
    private const val W = 595f
    private const val H = 842f
    private const val MARGIN_X = 72f
    private const val BOTTOM = 70f

    /** Strips light Markdown so prose reads cleanly. */
    private fun strip(body: String): List<String> =
        body.split("\n")
            .map {
                it.trim().replace("**", "").replace("~~", "")
            }
            .map { if (it.matches(Regex("---+"))) "* * *" else it }
            .filter { it.isNotEmpty() }

    fun build(plan: BookPlan, chapters: List<WrittenChapter>): ByteArray {
        val doc = PdfDocument()
        var pageNo = 0
        var page = newPage(doc, pageNo)
        var canvas = page.canvas
        var y = 0f

        fun openPage() {
            pageNo++
            page = newPage(doc, pageNo)
            canvas = page.canvas
            y = 130f
        }

        fun ensureRoom(needed: Float) {
            if (y + needed > H - BOTTOM) {
                footer()
                doc.finishPage(page)
                openPage()
            }
        }

        fun footer() {
            val p = Paint().apply {
                isAntiAlias = true
                color = Color.argb(150, 0, 0, 0)
                textSize = 9f
                textAlign = Paint.Align.CENTER
            }
            canvas.drawText((pageNo + 1).toString(), W / 2f, H - 34f, p)
        }

        // Title page.
        val titlePaint = Paint().apply {
            isAntiAlias = true
            typeface = Typeface.create(Typeface.SERIF, Typeface.BOLD)
            textSize = if (plan.title.length < 40) 30f else 24f
            textAlign = Paint.Align.CENTER
            color = Color.BLACK
        }
        val subPaint = Paint().apply {
            isAntiAlias = true
            typeface = Typeface.SERIF
            textSize = 13f
            textAlign = Paint.Align.CENTER
            color = Color.rgb(60, 60, 60)
        }
        val authorPaint = Paint().apply {
            isAntiAlias = true
            typeface = Typeface.SANS_SERIF
            textSize = 12f
            letterSpacing = 0.08f
            textAlign = Paint.Align.CENTER
            color = Color.BLACK
        }
        y = 280f
        plan.series.takeIf { it.isNotBlank() }?.let { s ->
            val p = Paint(subPaint).apply { textSize = 10f }
            canvas.drawText(s.uppercase(), W / 2f, y, p)
            y += 34f
        }
        y = drawWrapped(canvas, titlePaint, plan.title, W / 2f, y, W - MARGIN_X * 2)
        y += 30f
        if (plan.subtitle.isNotBlank()) {
            y = drawWrapped(canvas, subPaint, plan.subtitle, W / 2f, y, W - MARGIN_X * 2)
            y += 26f
        }
        y += 60f
        canvas.drawText(plan.author.uppercase(), W / 2f, y, authorPaint)
        y += 70f
        if (plan.tagline.isNotBlank()) {
            drawWrapped(canvas, subPaint, plan.tagline, W / 2f, y, W - MARGIN_X * 2)
        }
        footer()
        doc.finishPage(page)

        // Chapter pages share one flowing document.
        val bodyPaint = Paint().apply {
            isAntiAlias = true
            color = Color.BLACK
            textSize = 11f
        }
        val headPaint = Paint().apply {
            isAntiAlias = true
            typeface = Typeface.create(Typeface.SERIF, Typeface.BOLD)
            textSize = 15f
            color = Color.BLACK
        }

        openPage()
        chapters.forEachIndexed { i, ch ->
            ensureRoom(60f)
            y += 14f
            canvas.drawText(
                if (chapters.size > 1) "${i + 1}. ${ch.title}" else ch.title,
                MARGIN_X,
                y,
                headPaint,
            )
            y += 30f
            for (p in strip(ch.body)) {
                if (p == "* * *") {
                    ensureRoom(30f)
                    val d = Paint(bodyPaint).apply { textAlign = Paint.Align.CENTER }
                    canvas.drawText("* * *", W / 2f, y, d)
                    y += 40f
                    continue
                }
                var wrapped = wrapLines(p, bodyPaint, W - MARGIN_X * 2)
                wrapped.forEach { ln ->
                    ensureRoom(20f)
                    canvas.drawText(ln, MARGIN_X, y, bodyPaint)
                    y += 17f
                }
                y += 6f
            }
            y += 18f
        }
        footer()
        doc.finishPage(page)

        val out = ByteArrayOutputStream()
        doc.writeTo(out)
        doc.close()
        return out.toByteArray()
    }

    private fun newPage(doc: PdfDocument, pageNo: Int): PdfDocument.Page =
        doc.startPage(
            PdfDocument.PageInfo.Builder(W.toInt(), H.toInt(), pageNo + 1).create(),
        )

    private fun wrapLines(text: String, paint: Paint, maxWidth: Float): List<String> =
        buildList {
            var line = ""
            for (word in text.split(Regex("\\s+"))) {
                val candidate = if (line.isEmpty()) word else "$line $word"
                if (line.isNotEmpty() && paint.measureText(candidate) > maxWidth) {
                    add(line)
                    line = word
                } else {
                    line = candidate
                }
            }
            if (line.isNotEmpty()) add(line)
        }

    /** Draws [text] centred on [x], wrapping in words; returns the new baseline. */
    private fun drawWrapped(
        canvas: android.graphics.Canvas,
        paint: Paint,
        text: String,
        x: Float,
        startY: Float,
        maxWidth: Float,
    ): Float {
        var y = startY
        wrapLines(text, paint, maxWidth).forEach { ln ->
            canvas.drawText(ln, x, y, paint)
            y += paint.textSize * 1.35f
        }
        return y
    }
}
