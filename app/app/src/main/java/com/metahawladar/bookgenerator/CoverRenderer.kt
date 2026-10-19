package com.metahawladar.bookgenerator

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import java.io.ByteArrayOutputStream
import kotlin.math.max
import kotlin.random.Random

data class CoverTheme(
    val name: String,
    val sky: IntArray,
    val accent: Int,
    val title: Int,
    val scene: String,
) {
    override fun equals(other: Any?): Boolean = other is CoverTheme && other.name == name
    override fun hashCode(): Int = name.hashCode()

    companion object {
        val ALL: Map<String, CoverTheme> = linkedMapOf(
            "ember" to CoverTheme(
                "ember",
                intArrayOf(0xFF1A1040.toInt(), 0xFF3D1B6B.toInt(), 0xFF7B2D8E.toInt(),
                    0xFFC23B6B.toInt(), 0xFFE8663C.toInt(), 0xFFF59E42.toInt()),
                0xFFFFD27F.toInt(), 0xFFFFF4E0.toInt(), "town",
            ),
            "frost" to CoverTheme(
                "frost",
                intArrayOf(0xFF06121F.toInt(), 0xFF0D2A44.toInt(), 0xFF17496B.toInt(),
                    0xFF2D7A9C.toInt(), 0xFF78C4D4.toInt(), 0xFFD7F0F5.toInt()),
                0xFFA8E4F0.toInt(), 0xFFF2FBFF.toInt(), "town",
            ),
            "forest" to CoverTheme(
                "forest",
                intArrayOf(0xFF0B1A12.toInt(), 0xFF13301F.toInt(), 0xFF255138.toInt(),
                    0xFF4A7C4E.toInt(), 0xFF9BB86A.toInt(), 0xFFE3D58C.toInt()),
                0xFFE8C66A.toInt(), 0xFFFDF6E0.toInt(), "hills",
            ),
            "rose" to CoverTheme(
                "rose",
                intArrayOf(0xFF2A0F2E.toInt(), 0xFF56184F.toInt(), 0xFF8F2566.toInt(),
                    0xFFC74B72.toInt(), 0xFFEF8496.toInt(), 0xFFFFD0C4.toInt()),
                0xFFFFD9B8.toInt(), 0xFFFFF4F2.toInt(), "hills",
            ),
            "slate" to CoverTheme(
                "slate",
                intArrayOf(0xFF070D18.toInt(), 0xFF0B1626.toInt(), 0xFF102033.toInt(),
                    0xFF15293F.toInt(), 0xFF1B3350.toInt(), 0xFF223F61.toInt()),
                0xFF4DA3FF.toInt(), 0xFFFFFFFF.toInt(), "grid",
            ),
            "sand" to CoverTheme(
                "sand",
                intArrayOf(0xFF2B1D14.toInt(), 0xFF432C1D.toInt(), 0xFF5E4028.toInt(),
                    0xFF8A6238.toInt(), 0xFFBF9154.toInt(), 0xFFE8CF9C.toInt()),
                0xFFF0C987.toInt(), 0xFFFFF8EC.toInt(), "hills",
            ),
        )

        fun of(name: String, fiction: Boolean): CoverTheme =
            ALL[name] ?: ALL[if (fiction) "ember" else "slate"]!!
    }
}


/** Everything the cover studio can change without touching the code. */
data class CoverStyle(
    /** A key of CoverTheme.ALL, or "auto" to keep the planner's choice. */
    val theme: String = "auto",
    /** auto | center | left | bottom */
    val layout: String = "auto",
    /** auto | serif | sans */
    val font: String = "auto",
    /** Seeds the stars, embers and rooftops, so a reshuffle gives a new look. */
    val seed: Int = 42,
) {
    val label: String get() = "$theme - $layout - $font"

    companion object {
        val LAYOUTS = listOf("auto", "center", "left", "bottom")
        val FONTS = listOf("auto", "serif", "sans")
    }
}

/** One option shown in the cover studio. */
data class CoverVariant(val style: CoverStyle, val png: ByteArray)

object CoverRenderer {
    const val WIDTH = 1600
    const val HEIGHT = 2560
    private const val PAD = 110f

    /**
     * Renders the cover and returns PNG bytes (1600x2560).
     *
     * When [art] holds a generated image (see [Prompts.coverArt]) it is used
     * as the background and only the type is drawn on top; otherwise the
     * procedural theme scene is drawn as a fallback.
     */
    fun render(
        title: String,
        subtitle: String,
        series: String,
        tagline: String,
        author: String,
        themeName: String,
        fiction: Boolean,
        style: CoverStyle = CoverStyle(),
        art: ByteArray? = null,
    ): ByteArray {
        val resolved = if (style.theme == "auto" || style.theme.isBlank()) themeName else style.theme
        val t = CoverTheme.of(resolved, fiction)
        val bmp = Bitmap.createBitmap(WIDTH, HEIGHT, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val w = WIDTH.toFloat()
        val h = HEIGHT.toFloat()

        val drewArt = art != null && paintArtwork(canvas, art)
        if (!drewArt) {
            val stops = FloatArray(t.sky.size) { it / (t.sky.size - 1f) }
            canvas.drawRect(
                0f, 0f, w, h,
                Paint().apply {
                    shader = LinearGradient(0f, 0f, 0f, h, t.sky, stops, Shader.TileMode.CLAMP)
                },
            )

            if (t.scene == "grid") {
                val g = Paint().apply {
                    color = Color.argb(10, 255, 255, 255)
                    strokeWidth = 1f
                }
                var x = 0f
                while (x < w) { canvas.drawLine(x, 0f, x, h, g); x += 80f }
                var y = 0f
                while (y < h) { canvas.drawLine(0f, y, w, y, g); y += 80f }
            }

            val rnd = Random(style.seed)
            val starColors = intArrayOf(t.title, t.accent, 0xFFCBB8FF.toInt(), 0xFFFFD9C0.toInt())
            val radii = floatArrayOf(1f, 1f, 1f, 2f, 2f, 3f)
            repeat(300) {
                val sx = rnd.nextFloat() * w
                val sy = rnd.nextFloat() * h * 0.72f
                val p = Paint().apply {
                    isAntiAlias = true
                    color = starColors[rnd.nextInt(starColors.size)]
                    alpha = (255 * (0.25f + rnd.nextFloat() * 0.7f)).toInt()
                }
                canvas.drawCircle(sx, sy, radii[rnd.nextInt(radii.size)], p)
            }

            val base = h * 0.78f

            if (t.scene != "grid") {
                canvas.drawRect(0f, base, w, h, Paint().apply { color = 0xFF1B1236.toInt() })
                canvas.drawOval(
                    RectF(w * 0.22f - w * 0.52f, base + 180 - 230, w * 0.22f + w * 0.52f, base + 180 + 230),
                    Paint().apply { isAntiAlias = true; color = 0xD92A1B45.toInt() },
                )
                canvas.drawOval(
                    RectF(w * 0.80f - w * 0.48f, base + 200 - 210, w * 0.80f + w * 0.48f, base + 200 + 210),
                    Paint().apply { isAntiAlias = true; color = 0xE6241740.toInt() },
                )
            }

            if (fiction) {
                val emberColors = intArrayOf(
                    t.accent, 0xFFFF9D4D.toInt(), 0xFFFFCF6B.toInt(), 0xFFFF7A3C.toInt()
                )
                repeat(140) {
                    val ex = w / 2 + (rnd.nextFloat() - 0.5f) * w * 0.42f
                    val ey = h * 0.40f + rnd.nextFloat() * h * 0.32f
                    val p = Paint().apply {
                        isAntiAlias = true
                        color = emberColors[rnd.nextInt(emberColors.size)]
                        alpha = (255 * (0.35f + rnd.nextFloat() * 0.6f)).toInt()
                    }
                    canvas.drawCircle(ex, ey, 2f + rnd.nextInt(4), p)
                }
            }

            if (t.scene == "town") drawTown(canvas, base, t, style.seed)
        }

        // ---- Type ----
        val left = when (style.layout) {
            "left" -> true
            "center", "bottom" -> false
            else -> !fiction
        }
        val align = if (left) Layout.Alignment.ALIGN_NORMAL else Layout.Alignment.ALIGN_CENTER
        var y = when (style.layout) {
            "left" -> 760f
            "center" -> 150f
            "bottom" -> h * 0.46f
            else -> if (left) 760f else 150f
        }
        val serif = Typeface.create(Typeface.SERIF, Typeface.NORMAL)
        val sans = Typeface.create(Typeface.SANS_SERIF, Typeface.NORMAL)
        val sansBold = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        val serifItalic = Typeface.create(Typeface.SERIF, Typeface.ITALIC)
        val useSerif = when (style.font) {
            "serif" -> true
            "sans" -> false
            else -> fiction
        }

        if (series.isNotEmpty()) {
            y += text(canvas, series.uppercase(), y, 38f, t.accent, align, sans, letterSpacing = 0.24f)
            y += 28f
            val ruleW = if (left) 230f else 170f
            canvas.drawRect(
                if (left) PAD else (w - ruleW) / 2, y,
                (if (left) PAD else (w - ruleW) / 2) + ruleW, y + 2f,
                Paint().apply { color = t.accent; alpha = 178 },
            )
            y += 50f
        } else if (left) {
            canvas.drawRect(PAD, y, PAD + 230f, y + 2f, Paint().apply { color = t.accent; alpha = 178 })
            y += 50f
        }

        val titleSize = when {
            title.length < 20 -> if (left) 180f else 150f
            title.length < 34 -> if (left) 144f else 118f
            else -> if (left) 112f else 92f
        }
        y += text(
            canvas, title, y, titleSize, t.title, align,
            if (useSerif) serif else sansBold, shadow = true,
        )

        if (subtitle.isNotEmpty()) {
            y += 40f
            y += text(
                canvas, subtitle, y, if (left) 52f else 46f,
                Color.argb(235, 255, 255, 255), align,
                if (useSerif) serifItalic else sans,
            )
        }
        if (tagline.isNotEmpty()) {
            y += 54f
            text(
                canvas, tagline, y, 40f, Color.argb(217, 255, 255, 255),
                align, serifItalic,
            )
        }

        text(
            canvas, author, h - 190f, 62f, t.title, align, sansBold,
            letterSpacing = 0.06f, shadow = true,
        )

        val out = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
        bmp.recycle()
        return out.toByteArray()
    }

    /**
     * Draws a generated artwork as the cover background, cropped to fill the
     * 1600x2560 frame, then lays a soft dark wash over it so the title and
     * author always stay readable. Returns false when the bytes do not decode.
     */
    private fun paintArtwork(canvas: Canvas, art: ByteArray): Boolean {
        val src = BitmapFactory.decodeByteArray(art, 0, art.size) ?: return false
        val w = WIDTH.toFloat()
        val h = HEIGHT.toFloat()
        val scale = max(w / src.width, h / src.height)
        val dx = (w - src.width * scale) / 2f
        val dy = (h - src.height * scale) / 2f
        canvas.save()
        canvas.scale(scale, scale)
        canvas.translate(dx / scale, dy / scale)
        canvas.drawBitmap(src, 0f, 0f, Paint().apply { isFilterBitmap = true })
        canvas.restore()
        src.recycle()
        canvas.drawRect(
            0f, 0f, w, h,
            Paint().apply {
                shader = LinearGradient(
                    0f, 0f, 0f, h,
                    intArrayOf(0x66000000, 0x22000000, 0x33000000, 0x99000000),
                    floatArrayOf(0f, 0.35f, 0.7f, 1f),
                    Shader.TileMode.CLAMP,
                )
            },
        )
        return true
    }

    private fun drawTown(canvas: Canvas, base: Float, t: CoverTheme, seed: Int) {
        val w = WIDTH.toFloat()
        val h = HEIGHT.toFloat()
        val rnd = Random(seed * 7 + 99)
        val body = Paint().apply { color = 0xFF16102B.toInt() }
        val blocks = ArrayList<RectF>()
        var x = 0f
        while (x < w) {
            val bw = 70f + rnd.nextInt(80)
            val bh = 90f + rnd.nextInt(140)
            blocks.add(RectF(x, base - bh, x + bw, h))
            x += bw + 4 + rnd.nextInt(18)
        }
        blocks.forEach { canvas.drawRect(it, body) }

        val win = Paint().apply {
            isAntiAlias = true
            shader = LinearGradient(
                0f, base - 200, 0f, base,
                0xFFFFF6D8.toInt(), t.accent, Shader.TileMode.CLAMP,
            )
        }
        val wr = Random(seed * 3 + 5)
        for (r in blocks) {
            val rows = 1 + wr.nextInt(3)
            val cols = max(1, (r.width() / 55f).toInt())
            for (row in 0 until rows) {
                for (col in 0 until cols) {
                    if (wr.nextFloat() < 0.45f) {
                        val wx = r.left + 14 + col * 50
                        val wy = r.top + 24 + row * 62
                        if (wx + 22 < r.right) {
                            canvas.drawRoundRect(RectF(wx, wy, wx + 20, wy + 30), 3f, 3f, win)
                        }
                    }
                }
            }
        }

        val cx = w / 2
        val focal = Paint().apply { isAntiAlias = true; color = 0xFF1A1230.toInt() }
        canvas.drawRect(cx - 150, base - 300, cx + 150, base + 40, focal)
        val roof = Path().apply {
            moveTo(cx, base - 400)
            lineTo(cx - 80, base - 290)
            lineTo(cx + 80, base - 290)
            close()
        }
        canvas.drawPath(roof, focal)
        for (i in -1..1) {
            val ax = cx + i * 86 - 34
            val arch = Path().apply {
                moveTo(ax, base - 30)
                lineTo(ax, base - 150)
                arcTo(RectF(ax, base - 184, ax + 68, base - 116), 180f, 180f, false)
                lineTo(ax + 68, base - 30)
                close()
            }
            canvas.drawPath(arch, win)
        }
        canvas.drawOval(
            RectF(cx - 150, base + 120 - 190, cx + 150, base + 120 + 190),
            Paint().apply {
                isAntiAlias = true
                color = t.accent
                alpha = 46
                maskFilter = BlurMaskFilter(60f, BlurMaskFilter.Blur.NORMAL)
            },
        )
    }

    /** Draws [value] and returns the height it consumed. */
    private fun text(
        canvas: Canvas,
        value: String,
        top: Float,
        size: Float,
        color: Int,
        align: Layout.Alignment,
        typeface: Typeface,
        letterSpacing: Float = 0f,
        shadow: Boolean = false,
    ): Float {
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            textSize = size
            this.typeface = typeface
            this.letterSpacing = letterSpacing
            if (shadow) setShadowLayer(40f, 0f, 2f, Color.argb(153, 0, 0, 0))
        }
        val maxWidth = (WIDTH - PAD * 2).toInt()
        val layout = StaticLayout.Builder
            .obtain(value, 0, value.length, paint, maxWidth)
            .setAlignment(align)
            .setLineSpacing(0f, 1.05f)
            .setIncludePad(false)
            .build()
        canvas.save()
        canvas.translate(PAD, top)
        layout.draw(canvas)
        canvas.restore()
        return layout.height.toFloat()
    }
}
