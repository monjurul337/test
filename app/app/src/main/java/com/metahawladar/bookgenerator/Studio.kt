package com.metahawladar.bookgenerator

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** What the cover studio hands back when you accept a cover. */
data class ChosenCover(val style: CoverStyle, val png: ByteArray)

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
    var style by remember { mutableStateOf(result.coverStyle) }
    var custom by remember { mutableStateOf<ByteArray?>(null) }

    LaunchedEffect(Unit) {
        val v = withContext(Dispatchers.Default) { writer.coverVariants(result) }
        variants = v
        style = v.first().style
        loading = false
    }

    suspend fun renderCustom() {
        rendering = true
        val png = withContext(Dispatchers.Default) {
            CoverRenderer.render(
                title = result.plan.title,
                subtitle = result.plan.subtitle,
                series = result.plan.series,
                tagline = result.plan.tagline,
                author = result.plan.author,
                themeName = if (style.theme == "auto") result.plan.theme else style.theme,
                fiction = result.request.fiction,
                style = style,
            )
        }
        custom = png
        selected = -1
        rendering = false
    }

    var renderTick by remember { mutableStateOf(0) }
    LaunchedEffect(renderTick) { if (renderTick > 0) renderCustom() }

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
                ) { CircularProgressIndicator() }
            } else {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    Text(
                        "Pick one of the four, or build your own below. The chosen " +
                            "cover is written into the EPUB and the ZIP.",
                        style = MaterialTheme.typography.bodySmall,
                    )
                    Spacer(Modifier.height(12.dp))
                    Row {
                        variants.forEachIndexed { i, v ->
                            Thumb(
                                png = v.png,
                                label = v.style.label,
                                selected = selected == i,
                                modifier = Modifier.weight(1f).padding(end = 6.dp),
                            ) {
                                selected = i
                                style = v.style
                            }
                        }
                        custom?.let { png ->
                            Thumb(
                                png = png,
                                label = "custom",
                                selected = selected == -1,
                                modifier = Modifier.weight(1f),
                            ) { selected = -1 }
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
                            Text("Shuffle")
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
                onClick = { current?.let { onChosen(ChosenCover(style, it)) } },
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
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val bmp = remember(png) { BitmapFactory.decodeByteArray(png, 0, png.size) }
    Column(modifier.clickable(onClick = onClick)) {
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
