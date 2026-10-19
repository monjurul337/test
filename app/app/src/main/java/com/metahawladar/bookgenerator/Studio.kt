package com.metahawladar.bookgenerator

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Autorenew
import androidx.compose.material.icons.filled.Casino
import androidx.compose.material.icons.filled.FactCheck
import androidx.compose.material.icons.filled.Link
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SmallFloatingActionButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.SelectionContainer
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/**
 * What the cover studio hands back when you accept a cover. [artUrl] is the
 * exact Gemini-session URL of that cover's artwork, so the applied result
 * publishes the right link - not just the most recent render's.
 */
data class ChosenCover(val style: CoverStyle, val png: ByteArray, val artUrl: String? = null)

/**
 * Four generated options plus manual colour, layout, font and shuffle
 * controls. Nothing is written to disk until the caller applies the result.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CoverStudioDialog(
    writer: BookWriter,
    result: BookResult,
    onDismiss: () -> Unit,
    onChosen: (ChosenCover) -> Unit,
) {
    var variants by remember { mutableStateOf<List<CoverVariant>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var rendering by remember { mutableStateOf(false) }
    var selected by remember { mutableStateOf(0) }
    var count by remember { mutableStateOf(4) }
    var breeding by remember { mutableStateOf(-1) }
    var reloadTick by remember { mutableStateOf(0) }
    var style by remember { mutableStateOf(result.coverStyle) }
    var custom by remember { mutableStateOf<ByteArray?>(null) }
    var status by remember { mutableStateOf("Generating cover artwork...") }

    /**
     * The exact URL of the newest Gemini-session artwork, synced live from
     * [BookWriter.lastCoverArtUrl] on every progress tick - cleared the
     * moment a new render starts, republished right when the bytes land,
     * never a stale or placeholder link.
     */
    var artUrl by remember { mutableStateOf<String?>(null) }
    var customUrl by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(reloadTick) {
        val v = writer.coverVariants(result, count) { _, m ->
            status = m
            artUrl = writer.lastCoverArtUrl
        }
        variants = v
        style = v.first().style
        artUrl = v.first().artUrl ?: writer.lastCoverArtUrl
        selected = 0
        loading = false
    }

    suspend fun renderCustom() {
        rendering = true
        val png = writer.renderCover(result, style) { _, m ->
            status = m
            artUrl = writer.lastCoverArtUrl
        }
        custom = png
        customUrl = writer.lastCoverArtUrl
        selected = -1
        artUrl = customUrl
        rendering = false
    }

    var renderTick by remember { mutableStateOf(0) }
    LaunchedEffect(renderTick) { if (renderTick > 0) renderCustom() }

    /** Redesigns one slot with a fresh seed - a brand new artwork, nothing else touched. */
    suspend fun redesignOne(i: Int) {
        if (breeding != -1 || i !in variants.indices) return
        breeding = i
        try {
            val st = variants[i].style.copy(
                seed = ((System.currentTimeMillis() % 1000000)).toInt(),
            )
            val png = writer.renderCover(result, st) { _, m ->
                status = m
                artUrl = writer.lastCoverArtUrl
            }
            val fresh = CoverVariant(st, png, writer.lastCoverArtUrl)
            variants = variants.toMutableList().also { it[i] = fresh }
            if (selected == i) {
                style = st
                artUrl = fresh.artUrl
            }
        } finally {
            breeding = -1
        }
    }

    var redesignTick by remember { mutableStateOf(-2) }
    LaunchedEffect(redesignTick) { if (redesignTick >= 0) redesignOne(redesignTick) }

    val current: ByteArray? =
        if (selected in variants.indices) variants[selected].png else custom

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Cover studio") },
        text = {
            if (loading) {
                Column(
                    Modifier.fillMaxWidth().height(180.dp),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    CircularProgressIndicator()
                    Spacer(Modifier.height(12.dp))
                    Text(status, style = MaterialTheme.typography.bodySmall)
                }
            } else {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    Text(
                        "Pick one of the ${variants.size} covers, redesign any " +
                            "slot, or build your own below. The chosen cover " +
                            "is written into the EPUB and the ZIP.",
                        style = MaterialTheme.typography.bodySmall,
                    )
                    Spacer(Modifier.height(12.dp))
                    Picker("Cover options", listOf("2", "3", "4", "5", "6", "8"), count.toString()) {
                        count = it.toInt()
                        reloadTick++
                    }
                    Spacer(Modifier.height(12.dp))
                    variants.chunked(4).forEach { row ->
                        Row {
                            row.forEach { v ->
                                val i = variants.indexOf(v)
                                Thumb(
                                    png = v.png,
                                    label = v.style.label,
                                    selected = selected == i,
                                    busy = breeding == i,
                                    modifier = Modifier.weight(1f).padding(end = 6.dp),
                                    onRedesign = { redesignTick = i },
                                    onClick = {
                                        selected = i
                                        style = v.style
                                        artUrl = v.artUrl
                                    },
                                )
                            }
                        }
                        Spacer(Modifier.height(8.dp))
                    }
                    custom?.let { png ->
                        Row {
                            Thumb(
                                png = png,
                                label = "custom",
                                selected = selected == -1,
                                modifier = Modifier.weight(1f),
                            ) {
                                selected = -1
                                artUrl = customUrl
                            }
                        }
                    }
                    if (breeding != -1) {
                        Spacer(Modifier.height(6.dp))
                        Text(status, style = MaterialTheme.typography.labelSmall)
                    }
                    Spacer(Modifier.height(14.dp))
                    Card {
                        Column(Modifier.padding(10.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(
                                    Icons.Filled.Link,
                                    contentDescription = null,
                                    modifier = Modifier.size(14.dp),
                                    tint = MaterialTheme.colorScheme.primary,
                                )
                                Spacer(Modifier.width(6.dp))
                                Text(
                                    "Artwork source - served by the Gemini session:",
                                    style = MaterialTheme.typography.labelSmall,
                                )
                            }
                            Spacer(Modifier.height(4.dp))
                            val u = artUrl
                            if (u.isNullOrEmpty()) {
                                Text(
                                    "None - inline API artwork has no public " +
                                        "URL, or the drawn procedural cover " +
                                        "is in use.",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            } else {
                                SelectionContainer {
                                    Text(
                                        u,
                                        style = MaterialTheme.typography.bodySmall,
                                        fontFamily = FontFamily.Monospace,
                                        maxLines = 4,
                                    )
                                }
                            }
                        }
                    }
                    HorizontalDivider(Modifier.padding(vertical = 14.dp))
                    Picker("Colour", CoverTheme.ALL.keys.toList(), style.theme) {
                        style = style.copy(theme = it)
                    }
                    Spacer(Modifier.height(10.dp))
                    Picker("Layout", CoverStyle.LAYOUTS, style.layout) {
                        style = style.copy(layout = it)
                    }
                    Spacer(Modifier.height(10.dp))
                    Picker("Font", CoverStyle.FONTS, style.font) {
                        style = style.copy(font = it)
                    }
                    Spacer(Modifier.height(12.dp))
                    Row {
                        FilledTonalButton(
                            onClick = { renderTick++ },
                            enabled = !rendering,
                        ) { Text("Preview my settings") }
                        Spacer(Modifier.width(8.dp))
                        FilledTonalButton(
                            onClick = {
                                style = style.copy(
                                    seed = (System.currentTimeMillis() % 100000).toInt(),
                                )
                                renderTick++
                            },
                            enabled = !rendering,
                        ) {
                            Icon(Icons.Filled.Casino, contentDescription = null)
                            Spacer(Modifier.width(6.dp))
                            Text("Shuffle art")
                        }
                        if (rendering) {
                            Spacer(Modifier.width(12.dp))
                            CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                        }
                    }
                }
            }
        },
        confirmButton = {
            Button(
                onClick = { current?.let { onChosen(ChosenCover(style, it, artUrl)) } },
                enabled = current != null,
            ) { Text("Use this cover") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@Composable
private fun Thumb(
    png: ByteArray,
    label: String,
    selected: Boolean,
    busy: Boolean = false,
    modifier: Modifier = Modifier,
    onRedesign: (() -> Unit)? = null,
    onClick: () -> Unit,
) {
    val bmp = remember(png) { BitmapFactory.decodeByteArray(png, 0, png.size) }
    Column(modifier.clickable(onClick = onClick)) {
        Box {
            if (bmp != null) {
                Image(
                    bitmap = bmp.asImageBitmap(),
                    contentDescription = label,
                    modifier = Modifier
                        .fillMaxWidth()
                        .aspectRatio(1600f / 2560f)
                        .clip(RoundedCornerShape(6.dp))
                        .border(
                            width = if (selected) 3.dp else 1.dp,
                            color = if (selected) GOLD else Color(0x33FFFFFF),
                            shape = RoundedCornerShape(6.dp),
                        ),
                )
            }
            if (onRedesign != null) {
                SmallFloatingActionButton(
                    onClick = { if (!busy) onRedesign() },
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(4.dp)
                        .size(24.dp),
                    containerColor = Color(0xD9000000),
                    contentColor = Color.White,
                ) {
                    if (busy) {
                        CircularProgressIndicator(
                            Modifier.size(14.dp),
                            strokeWidth = 2.dp,
                            color = Color.White,
                        )
                    } else {
                        Icon(
                            Icons.Filled.Autorenew,
                            contentDescription = "Redesign",
                            modifier = Modifier.size(13.dp),
                        )
                    }
                }
            }
        }
        Spacer(Modifier.height(4.dp))
        Text(label, style = MaterialTheme.typography.labelSmall, maxLines = 2)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Picker(
    label: String,
    options: List<String>,
    value: String,
    onPick: (String) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(expanded = open, onExpandedChange = { open = !open }) {
        OutlinedTextField(
            value = value,
            onValueChange = {},
            readOnly = true,
            label = { Text(label) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(open) },
            modifier = Modifier
                .fillMaxWidth()
                .menuAnchor(androidx.compose.material3.MenuAnchorType.PrimaryNotEditable),
        )
        ExposedDropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            options.forEach { o ->
                DropdownMenuItem(
                    text = { Text(o) },
                    onClick = {
                        onPick(o)
                        open = false
                    },
                )
            }
        }
    }
}

/** The editor report, with a one-tap rewrite for every chapter it flags. */
@Composable
fun QualityCard(
    report: QualityReport,
    busy: Boolean,
    onFix: (Int, String) -> Unit,
) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.FactCheck, contentDescription = null, tint = GOLD)
                Spacer(Modifier.width(8.dp))
                Text(
                    "Editor report",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold,
                    color = GOLD,
                )
                Spacer(Modifier.weight(1f))
                Text(
                    "${report.score}/100",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                )
            }
            Spacer(Modifier.height(8.dp))
            Text(report.verdict, style = MaterialTheme.typography.bodySmall)
            if (report.issues.isEmpty()) {
                Spacer(Modifier.height(8.dp))
                Text("No issues found.", style = MaterialTheme.typography.bodySmall)
            }
            report.issues.forEach { i ->
                Spacer(Modifier.height(12.dp))
                val where = if (i.chapter == 0) "" else "  -  chapter ${i.chapter}"
                Text(
                    "${i.severity.uppercase()}  ${i.type}$where",
                    style = MaterialTheme.typography.labelSmall,
                    color = when (i.severity) {
                        "high" -> Color(0xFFFF6B6B)
                        "medium" -> GOLD
                        else -> Color(0xFF9E9E9E)
                    },
                )
                Text(i.detail, style = MaterialTheme.typography.bodySmall)
                if (i.fix.isNotBlank()) {
                    Text(
                        "Fix: ${i.fix}",
                        style = MaterialTheme.typography.bodySmall,
                        fontStyle = FontStyle.Italic,
                    )
                }
                if (i.chapter > 0) {
                    TextButton(
                        onClick = { onFix(i.chapter - 1, "${i.detail}\n\nRequired fix: ${i.fix}") },
                        enabled = !busy,
                    ) {
                        Icon(Icons.Filled.Autorenew, contentDescription = null)
                        Spacer(Modifier.width(6.dp))
                        Text("Rewrite chapter ${i.chapter}")
                    }
                }
            }
        }
    }
}

/** Asks what should change before a chapter is rewritten. */
@Composable
fun RewriteDialog(
    chapterNumber: Int,
    chapterTitle: String,
    initialNote: String,
    onDismiss: () -> Unit,
    onConfirm: (String) -> Unit,
) {
    var note by remember { mutableStateOf(initialNote) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Rewrite chapter $chapterNumber") },
        text = {
            Column {
                Text(chapterTitle, style = MaterialTheme.typography.bodySmall)
                Spacer(Modifier.height(10.dp))
                OutlinedTextField(
                    value = note,
                    onValueChange = { note = it },
                    label = { Text("What should change?") },
                    placeholder = { Text("Too slow, cut the flashback, raise the stakes") },
                    minLines = 3,
                    maxLines = 6,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            Button(onClick = { onConfirm(note.trim()) }) { Text("Rewrite") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}
