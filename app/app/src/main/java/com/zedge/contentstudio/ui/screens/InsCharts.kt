package com.zedge.contentstudio.ui.screens

import android.graphics.Paint
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.background
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.ln
import kotlin.math.min
import kotlin.math.sin

/** v39: donut chart for "Split by revenue type" (same look as the Zedge dashboard). */
@Composable
internal fun InsDonut(values: List<Double>, colors: List<Color>, labelColor: Color, size: Dp = 190.dp) {
    Canvas(Modifier.size(size)) {
        val tot = values.sumOf { if (it > 0) it else 0.0 }
        if (tot <= 0) return@Canvas
        val pad = 26.dp.toPx()
        val outer = this.size.minDimension / 2 - pad
        val sw = outer * 0.48f
        val r = outer - sw / 2
        val tl = Offset(center.x - r, center.y - r)
        val n = values.count { it > 0 }
        val txt = Paint().apply { isAntiAlias = true; color = labelColor.toArgb(); textSize = 11.dp.toPx(); isFakeBoldText = true }
        var a0 = -90.0
        values.forEachIndexed { i, v ->
            if (v <= 0) return@forEachIndexed
            val sweep = v / tot * 360.0
            val g = if (n > 1) min(1.6, sweep / 2) else 0.0
            drawArc(
                color = colors[i % colors.size].copy(alpha = 0.9f),
                startAngle = (a0 + g / 2).toFloat(),
                sweepAngle = (sweep - g).toFloat(),
                useCenter = false,
                topLeft = tl,
                size = Size(r * 2, r * 2),
                style = Stroke(width = sw, cap = StrokeCap.Butt),
            )
            val mid = (a0 + sweep / 2) * PI / 180
            val lr = outer + 10.dp.toPx()
            val label = String.format("%.1f%%", v / tot * 100)
            val w = txt.measureText(label)
            val cx = cos(mid).toFloat()
            val x = center.x + cx * lr + (if (cx > 0.25f) 0f else if (cx < -0.25f) -w else -w / 2)
            val y = center.y + sin(mid).toFloat() * lr + txt.textSize / 3
            drawContext.canvas.nativeCanvas.drawText(label, x, y, txt)
            a0 += sweep
        }
    }
}

private class InsMapShape(val path: Path, val rings: List<FloatArray>)

private val insMapShapes: Map<String, InsMapShape> by lazy {
    WorldMapData.countries.mapValues { (_, v) ->
        val path = Path()
        val rings = ArrayList<FloatArray>()
        for (ring in v.split('|')) {
            val pts = ring.split(' ')
            val arr = FloatArray(pts.size * 2)
            var j = 0
            for (p in pts) {
                val c = p.indexOf(',')
                if (c <= 0) continue
                arr[j++] = p.substring(0, c).toFloatOrNull() ?: 0f
                arr[j++] = p.substring(c + 1).toFloatOrNull() ?: 0f
            }
            if (j < 6) continue
            val a = if (j == arr.size) arr else arr.copyOf(j)
            rings.add(a)
            path.moveTo(a[0], a[1])
            var k = 2
            while (k < a.size) { path.lineTo(a[k], a[k + 1]); k += 2 }
            path.close()
        }
        InsMapShape(path, rings)
    }
}

private fun insInside(r: FloatArray, x: Float, y: Float): Boolean {
    var inside = false
    var j = r.size - 2
    var i = 0
    while (i < r.size) {
        val xi = r[i]; val yi = r[i + 1]; val xj = r[j]; val yj = r[j + 1]
        if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) inside = !inside
        j = i; i += 2
    }
    return inside
}

/** v39: world map coloured by revenue per country. Tap a country to see its amount. */
@Composable
internal fun InsWorldMap(values: Map<String, Double>, names: Map<String, String>, money: (Double) -> String) {
    var sel by remember { mutableStateOf<String?>(null) }
    val empty = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.10f)
    val line = MaterialTheme.colorScheme.surface
    val mx = values.values.maxOrNull() ?: 0.0
    val lmx = ln(1 + mx * 100)
    Box(Modifier.fillMaxWidth()) {
        Canvas(
            Modifier
                .fillMaxWidth()
                .aspectRatio(WorldMapData.W / WorldMapData.H)
                .pointerInput(values) {
                    detectTapGestures { o ->
                        val s = size.width / WorldMapData.W
                        val x = o.x / s; val y = o.y / s
                        sel = values.keys.firstOrNull { k -> insMapShapes[k]?.rings?.any { insInside(it, x, y) } == true }
                    }
                },
        ) {
            val s = size.width / WorldMapData.W
            scale(s, s, pivot = Offset.Zero) {
                for ((k, shp) in insMapShapes) {
                    val v = values[k]
                    var col = empty
                    if (v != null) {
                        val t = if (lmx > 0) (ln(1 + v * 100) / lmx).toFloat().coerceIn(0f, 1f) else 0f
                        col = lerp(Color(0xFFC9E3FF), Color(0xFF008CDF), t)
                        if (k == sel) col = lerp(col, Color.Black, 0.2f)
                    }
                    drawPath(shp.path, col)
                    drawPath(shp.path, line, style = Stroke(width = 0.8f))
                }
            }
        }
        val k = sel
        if (k != null) {
            Text(
                "${names[k] ?: k}  ${money(values[k] ?: 0.0)}",
                Modifier.align(Alignment.TopStart).padding(6.dp).background(Color(0xFF008CDF), RoundedCornerShape(6.dp)).padding(horizontal = 10.dp, vertical = 5.dp),
                color = Color.White,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Bold,
            )
        }
    }
}
