package com.metahawladar.bookgenerator

import android.content.Intent
import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material.icons.filled.SwipeUp
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.FileProvider
import java.io.File

/** Opens [file] with the system's default EPUB handler (Play Books etc.). */
fun openFile(context: android.content.Context, file: File) {
    try {
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        context.startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/epub+zip")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    } catch (e: Exception) {
        shareFile(context, file)
    }
}

/** Strips light Markdown so prose reads cleanly. */
private fun paragraphs(body: String): List<String> =
    body.replace(Regex("(?m)^#{1,6}\\s*"), "")
        .replace("---", "")
        .split("\n")
        .map { it.trim().replace("**", "").replace("~~", "") }
        .filter { it.isNotEmpty() }

/**
 * The reader - one long sheet of paper you scroll from the cover through
 * every chapter, the way a continuous-scroll ereader behaves. No Next
 * buttons; the thin progress bar under the header fills as you read.
 */
@Composable
fun BookPreviewDialog(r: BookResult, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val scroll = rememberScrollState()
    val progress by remember {
        derivedStateOf {
            if (scroll.maxValue > 0) scroll.value.toFloat() / scroll.maxValue else 0f
        }
    }
    // Cover decoded once; shown as the first block of the sheet.
    val cover = remember(r.cover.path) {
        BitmapFactory.decodeFile(r.cover.path)?.asImageBitmap()
    }
    val bodyColor = Color(0xFF1A1A1A)

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Surface(
            color = Color(0xFF2A2531),
            tonalElevation = 2.dp,
            modifier = Modifier
                .fillMaxSize()
                .padding(vertical = 24.dp)
                .clip(RoundedCornerShape(16.dp)),
        ) {
            Column(Modifier.fillMaxSize()) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 10.dp),
                ) {
                    Icon(Icons.Filled.MenuBook, contentDescription = null, tint = GOLD)
                    Spacer(Modifier.width(10.dp))
                    Text(
                        "Preview - ${r.plan.title}",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Bold,
                        maxLines = 1,
                        overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f),
                    )
                    TextButton(onClick = { openFile(context, r.epub) }) {
                        Text("Open EPUB")
                    }
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Filled.Close, contentDescription = "Close")
                    }
                }
                LinearProgressIndicator(
                    progress = { progress },
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                )
                Column(
                    Modifier
                        .weight(1f)
                        .verticalScroll(scroll)
                        .padding(horizontal = 14.dp, vertical = 14.dp),
                ) {
                    // The paper sheet: white, continuous, cover first.
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .background(Color.White, RoundedCornerShape(4.dp))
                            .padding(horizontal = 26.dp, vertical = 32.dp),
                    ) {
                        if (cover != null) {
                            Image(
                                bitmap = cover,
                                contentDescription = "Cover",
                                contentScale = ContentScale.FillWidth,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clip(RoundedCornerShape(4.dp))
                                    .padding(bottom = 30.dp),
                            )
                        }
                        r.chapters.forEach { ch ->
                            Text(
                                ch.title,
                                fontFamily = FontFamily.Serif,
                                fontWeight = FontWeight.Bold,
                                fontSize = 19.sp,
                                color = bodyColor,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(bottom = 16.dp),
                            )
                            paragraphs(ch.body).forEach { p ->
                                Text(
                                    p,
                                    fontFamily = FontFamily.Serif,
                                    fontSize = 15.sp,
                                    lineHeight = 24.sp,
                                    textAlign = TextAlign.Justify,
                                    color = bodyColor,
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(bottom = 12.dp),
                                )
                            }
                            Spacer(Modifier.height(24.dp))
                        }
                    }
                }
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 10.dp),
                ) {
                    Icon(Icons.Filled.SwipeUp, contentDescription = null, tint = GOLD, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(8.dp))
                    Text(
                        "Scroll to read - cover to last chapter, no Next buttons.",
                        style = MaterialTheme.typography.labelSmall,
                    )
                }
            }
        }
    }
}
