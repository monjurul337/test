package com.metahawladar.bookgenerator

import android.content.Intent
import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.MenuBook
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

/** One part of the paged preview. */
private data class PreviewPage(
    val isCover: Boolean,
    val heading: String?,
    val paragraphs: List<String>,
)

/** Strips light Markdown so prose reads cleanly. */
private fun paragraphs(body: String): List<String> =
    body.replace(Regex("(?m)^#{1,6}\\s*"), "")
        .replace("---", "")
        .split("\n")
        .map { it.trim().replace("**", "").replace("~~", "") }
        .filter { it.isNotEmpty() }

/** Pages: cover first, then the chapters filled with paragraphs. */
private fun paginate(chapters: List<WrittenChapter>, wordsPerPage: Int): List<PreviewPage> {
    val pages = ArrayList<PreviewPage>()
    pages.add(PreviewPage(true, null, emptyList()))
    for ((i, ch) in chapters.withIndex()) {
        var current = ArrayList<String>()
        var words = 0
        var firstPage = true
        fun flush() {
            if (current.isEmpty()) return
            pages.add(PreviewPage(false, "${i + 1}. ${ch.title}", current))
            firstPage = false
            current = ArrayList()
            words = 0
        }
        for (p in paragraphs(ch.body)) {
            val w = p.split(Regex("\\s+")).count { it.isNotEmpty() }
            if (words + w > wordsPerPage && current.isNotEmpty()) flush()
            current.add(p)
            words += w
        }
        flush()
    }
    return pages
}

/**
 * The paged reader - the paper, the serif type and the page numbers are a
 * close cousin of the Google Play Books layout.
 */
@Composable
fun BookPreviewDialog(r: BookResult, onDismiss: () -> Unit) {
    val context = LocalContext.current

    // Phone pages hold fewer lines than a phone-safe width allows.
    val wordsPerPage = 170
    val pages = remember(r) { paginate(r.chapters, wordsPerPage) }
    val cover = remember(r.cover.path) {
        BitmapFactory.decodeFile(r.cover.path)?.asImageBitmap()
    }
    val pagerState = rememberPagerState(pageCount = { pages.size })

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
                HorizontalPager(state = pagerState, modifier = Modifier.weight(1f)) { i ->
                    if (pages[i].isCover) {
                        Box(
                            Modifier
                                .fillMaxSize()
                                .padding(24.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            if (cover != null) {
                                Image(
                                    bitmap = cover,
                                    contentDescription = "Cover",
                                    contentScale = ContentScale.Fit,
                                    modifier = Modifier
                                        .clip(RoundedCornerShape(6.dp)),
                                )
                            }
                        }
                    } else {
                        TextPage(page = pages[i], pageNo = i + 1)
                    }
                }
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 10.dp),
                ) {
                    Text(
                        "Rough Google Play Books look - final spacing is set by the reader.",
                        style = MaterialTheme.typography.labelSmall,
                        modifier = Modifier.weight(1f),
                    )
                    Text("${pagerState.currentPage + 1} / ${pages.size}",
                        style = MaterialTheme.typography.labelSmall)
                }
            }
        }
    }
}

@Composable
private fun TextPage(page: PreviewPage, pageNo: Int) {
    val bodyColor = Color(0xFF1A1A1A)
    Column(
        Modifier
            .fillMaxSize()
            .padding(horizontal = 10.dp, vertical = 12.dp),
    ) {
        Column(
            Modifier
                .fillMaxSize()
                .background(Color.White, RoundedCornerShape(3.dp))
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 26.dp, vertical = 32.dp),
        ) {
            page.heading?.let { h ->
                Text(
                    h,
                    textAlign = TextAlign.Center,
                    fontFamily = FontFamily.Serif,
                    fontWeight = FontWeight.Bold,
                    fontSize = 19.sp,
                    color = bodyColor,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(bottom = 22.dp),
                )
            }
            page.paragraphs.forEachIndexed { idx, p ->
                Text(
                    p,
                    fontFamily = FontFamily.Serif,
                    fontSize =
                        if (page.paragraphs.size > 5) 13.sp else 15.sp,
                    lineHeight = 22.sp,
                    textAlign = TextAlign.Justify,
                    color = bodyColor,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(bottom = 12.dp),
                )
                if (idx == page.paragraphs.lastIndex) {
                    Text(
                        "$pageNo",
                        textAlign = TextAlign.Center,
                        fontSize = 11.sp,
                        color = Color(0x88000000),
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 6.dp),
                    )
                }
            }
        }
    }
}
