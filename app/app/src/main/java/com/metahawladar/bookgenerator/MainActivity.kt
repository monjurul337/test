package com.metahawladar.bookgenerator

import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Bundle
import android.os.Environment
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AutoStories
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Key
import androidx.compose.material.icons.filled.KeyOff
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.StopCircle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.DrawerValue
import androidx.compose.material3.ModalDrawerSheet
import androidx.compose.material3.ModalNavigationDrawer
import androidx.compose.material3.NavigationDrawerItem
import androidx.compose.material3.NavigationDrawerItemDefaults
import androidx.compose.material3.rememberDrawerState
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import androidx.compose.runtime.mutableStateListOf

const val APP_NAME = "Book Generator"
const val TAGLINE = "Meta Hawladar Team"
private const val PREFS = "book_generator"

/** Google Play Books counts roughly this many words per printed page. */
private const val WORDS_PER_PAGE = 250

/** LitPal-style light house style: white cards on a faint violet wash. */
val VIOLET = Color(0xFF7C3AED)
val VIOLET_DARK = Color(0xFF6D28D9)
val VIOLET_WASH = Color(0xFFF5F0FF)
val INK = Color(0xFF0C0A09)
val MUTED_INK = Color(0xFF78716C)
val LINE = Color(0xFFE7E5E4)
val MUTED = Color(0xFFF5F5F4)

/** Kept under the old name so existing call sites stay valid. */
val GOLD = VIOLET

fun appGradient(): Brush = Brush.verticalGradient(
    0.00f to Color(0xFFFBF8FF),
    0.35f to Color(0xFFF7F1FF),
    1.00f to Color(0xFFFFFFFF),
)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            MaterialTheme(
                colorScheme = lightColorScheme(
                    primary = VIOLET,
                    onPrimary = Color.White,
                    primaryContainer = VIOLET_WASH,
                    onPrimaryContainer = VIOLET_DARK,
                    secondary = VIOLET_DARK,
                    onSecondary = Color.White,
                    secondaryContainer = MUTED,
                    onSecondaryContainer = INK,
                    surface = Color.White,
                    onSurface = INK,
                    surfaceVariant = MUTED,
                    onSurfaceVariant = MUTED_INK,
                    surfaceContainer = Color.White,
                    surfaceContainerHigh = MUTED,
                    surfaceContainerHighest = MUTED,
                    surfaceContainerLow = Color.White,
                    surfaceContainerLowest = Color.White,
                    background = Color(0xFFFBF8FF),
                    onBackground = INK,
                    outline = LINE,
                    outlineVariant = LINE,
                    error = Color(0xFFEF4444),
                    onError = Color.White,
                )
            ) {
                Box(Modifier.fillMaxSize().background(appGradient())) {
                    HomeScreen()
                }
            }
        }
    }
}

private fun outputRoot(context: Context): File =
    File(
        context.getExternalFilesDir(Environment.DIRECTORY_DOCUMENTS)
            ?: context.filesDir,
        "BookGenerator",
    ).apply { mkdirs() }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen() {
    val context = androidx.compose.ui.platform.LocalContext.current
    val prefs = remember { context.getSharedPreferences(PREFS, Context.MODE_PRIVATE) }
    val scope = rememberCoroutineScope()
    val snackbar = remember { SnackbarHostState() }

    var apiKey by remember { mutableStateOf("") }
    var nvKey by remember { mutableStateOf(prefs.getString("nvKey", "") ?: "") }
    var provider by remember {
        mutableStateOf(prefs.getString("provider", Providers.GEMINI) ?: Providers.GEMINI)
    }
    var author by remember {
        mutableStateOf(prefs.getString("author", "Md Monjurul Islam") ?: "Md Monjurul Islam")
    }
    var model by remember {
        mutableStateOf(
            Providers.fixModel(
                prefs.getString("provider", Providers.GEMINI) ?: Providers.GEMINI,
                prefs.getString("model", Providers.defaultModel(Providers.GEMINI)) ?: Providers.defaultModel(Providers.GEMINI),
            )
        )
    }
    var coverArt by remember {
        mutableStateOf(
            ImageGen.fixModel(
                prefs.getString("provider", Providers.GEMINI) ?: Providers.GEMINI,
                prefs.getString("coverArt", ImageGen.OFF) ?: ImageGen.OFF,
            )
        )
    }

    /** The keys that belong to the provider in use right now. */
    val activeKeys = if (provider == Providers.NVIDIA) nvKey else apiKey
    var topic by remember { mutableStateOf("") }
    var note by remember { mutableStateOf("") }
    var bio by remember { mutableStateOf(prefs.getString("bio", "") ?: "") }
    var alsoBy by remember { mutableStateOf(prefs.getString("alsoBy", "") ?: "") }
    var publisher by remember { mutableStateOf(prefs.getString("publisher", "") ?: "") }
    var newsletter by remember { mutableStateOf(prefs.getString("newsletter", "") ?: "") }
    var showExtras by remember { mutableStateOf(false) }
    var chapters by remember { mutableStateOf("16") }
    var words by remember { mutableStateOf("15000") }
    var pages by remember { mutableStateOf("60") }
    var fiction by remember { mutableStateOf(true) }
    var theme by remember { mutableStateOf("auto") }
    var busy by remember { mutableStateOf(false) }
    var progress by remember { mutableStateOf(0f) }
    var result by remember { mutableStateOf<BookResult?>(null) }
    val results = remember { androidx.compose.runtime.mutableStateListOf<BookResult>() }
    var batchZip by remember { mutableStateOf<File?>(null) }
    var bookIndex by remember { mutableStateOf(0) }
    var bookTotal by remember { mutableStateOf(1) }
    var showKeyDialog by remember { mutableStateOf(false) }
    val log = remember { androidx.compose.runtime.mutableStateListOf<String>() }
    var writer by remember { mutableStateOf<BookWriter?>(null) }
    val listState = rememberLazyListState()

    var studioFor by remember { mutableStateOf<BookResult?>(null) }
    var rewriteFor by remember { mutableStateOf<BookResult?>(null) }
    var rewriteIndex by remember { mutableStateOf(0) }
    var rewriteNote by remember { mutableStateOf("") }
    var expandedChapters by remember { mutableStateOf<String?>(null) }

    var zipToSave by remember { mutableStateOf<File?>(null) }
    val saveZipLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/zip"),
    ) { uri ->
        val src = zipToSave
        if (uri != null && src != null) {
            runCatching {
                context.contentResolver.openOutputStream(uri)?.use { out ->
                    src.inputStream().use { it.copyTo(out) }
                }
            }.onSuccess {
                scope.launch { snackbar.showSnackbar("Saved ${'$'}{src.name}.") }
            }.onFailure {
                scope.launch { snackbar.showSnackbar("Could not save the ZIP.") }
            }
        }
    }

    LaunchedEffect(log.size) {
        if (log.isNotEmpty()) listState.animateScrollToItem(log.size - 1)
    }

    fun save() {
        prefs.edit()
            .remove("apiKey") // Session cookies are memory-only.
            .putString("nvKey", nvKey)
            .putString("provider", provider)
            .putString("author", author)
            .putString("model", model)
            .putString("coverArt", coverArt)
            .putString("bio", bio)
            .putString("alsoBy", alsoBy)
            .putString("publisher", publisher)
            .putString("newsletter", newsletter)
            .apply()
    }

    val topics = topic.split("\n").map { it.trim() }.filter { it.isNotEmpty() }

    fun replaceResult(old: BookResult, new: BookResult) {
        val i = results.indexOf(old)
        if (i >= 0) results[i] = new else results.add(new)
        if (result == old) result = new
    }

    /** Runs one post-production job and swaps the rebuilt book back in. */
    fun postJob(r: BookResult, job: suspend (BookWriter, (Float, String) -> Unit) -> BookResult) {
        busy = true
        progress = 0f
        val w = BookWriter(activeKeys, outputRoot(context))
        writer = w
        scope.launch {
            try {
                val out = withContext(Dispatchers.IO) {
                    job(w) { f, m ->
                        progress = f
                        log.add(m)
                        if (log.size > 400) log.removeAt(0)
                    }
                }
                replaceResult(r, out)
            } catch (e: Exception) {
                log.add("ERROR: ${e.message}")
                snackbar.showSnackbar(e.message ?: "Failed")
            } finally {
                busy = false
                writer = null
            }
        }
    }

    fun start() {
        if (topics.isEmpty()) {
            scope.launch { snackbar.showSnackbar("Type a topic first.") }
            return
        }
        if (activeKeys.isBlank()) { showKeyDialog = true; return }
        val nChapters = chapters.toIntOrNull() ?: 16
        val nWords = words.toIntOrNull() ?: 15000
        if (nChapters !in 1..60) {
            scope.launch { snackbar.showSnackbar("Chapters must be between 1 and 60.") }
            return
        }
        if (nWords !in 2000..150000) {
            scope.launch { snackbar.showSnackbar("Total words must be between 2,000 and 150,000.") }
            return
        }
        save()
        busy = true
        progress = 0f
        result = null
        results.clear()
        batchZip = null
        bookTotal = topics.size
        bookIndex = 0
        log.clear()
        val nKeys = if (provider == Providers.GEMINI) 1 else KeyPool.parse(activeKeys).size
        log.add(
            if (provider == Providers.GEMINI) "Using Gemini cookie session (web-selected model)."
            else "Using $nKeys NVIDIA keys, model $model."
        )
        if (topics.size > 1) log.add("Batch: ${topics.size} books queued.")
        val root = outputRoot(context)
        val w = BookWriter(activeKeys, root)
        writer = w
        val queue = topics.toList()
        scope.launch {
            var failed = 0
            try {
                for ((i, t) in queue.withIndex()) {
                    bookIndex = i + 1
                    if (queue.size > 1) {
                        log.add("")
                        log.add("=== Book ${i + 1}/${queue.size}: $t")
                    }
                    try {
                        val r = withContext(Dispatchers.IO) {
                            w.run(
                                BookRequest(
                                    topic = t,
                                    author = author.trim().ifBlank { "Anonymous" },
                                    fiction = fiction,
                                    chapters = nChapters,
                                    totalWords = nWords,
                                    model = model,
                                    provider = provider,
                                    coverArtModel = coverArt,
                                    themeOverride = if (theme == "auto") null else theme,
                                    note = note.trim(),
                                    extras = BookExtras(
                                        authorBio = bio.trim(),
                                        alsoBy = alsoBy.split("\n")
                                            .map { it.trim() }.filter { it.isNotEmpty() },
                                        publisher = publisher.trim(),
                                        newsletter = newsletter.trim(),
                                    ),
                                )
                            ) { f, m ->
                                progress = (i + f) / queue.size
                                log.add(m)
                                if (log.size > 400) log.removeAt(0)
                            }
                        }
                        result = r
                        results.add(r)
                    } catch (e: BookWriter.CancellationRequested) {
                        log.add("Batch stopped by you.")
                        break
                    } catch (e: Exception) {
                        failed++
                        log.add("ERROR on book ${i + 1}: ${e.message}")
                        if (queue.size == 1) snackbar.showSnackbar(e.message ?: "Failed")
                    }
                }
                if (results.size > 1) {
                    log.add("Packing all ${results.size} books into one ZIP...")
                    val all = results.toList()
                    batchZip = withContext(Dispatchers.IO) {
                        BookWriter.packBatch(all, root)
                    }
                    log.add("Batch ZIP ready.")
                }
                if (queue.size > 1) {
                    snackbar.showSnackbar(
                        "Batch done: ${results.size} written" +
                            if (failed > 0) ", $failed failed." else "."
                    )
                }
            } finally {
                busy = false
                progress = if (results.isEmpty()) 0f else 1f
                writer = null
            }
        }
    }

    studioFor?.let { r ->
        CoverStudioDialog(
            writer = BookWriter(activeKeys, outputRoot(context)),
            result = r,
            onDismiss = { studioFor = null },
            onChosen = { chosen ->
                studioFor = null
                postJob(r) { w, p -> w.applyCoverStyle(r, chosen.style, p, chosen.png) }
            },
        )
    }

    rewriteFor?.let { r ->
        RewriteDialog(
            chapterNumber = rewriteIndex + 1,
            chapterTitle = r.chapters.getOrNull(rewriteIndex)?.title ?: "",
            initialNote = rewriteNote,
            onDismiss = { rewriteFor = null },
            onConfirm = { n ->
                rewriteFor = null
                postJob(r) { w, p -> w.regenerateChapter(r, rewriteIndex, n, p) }
            },
        )
    }

    if (showKeyDialog) {
        var gDraft by remember { mutableStateOf(apiKey) }
        var nDraft by remember { mutableStateOf(nvKey) }
        var sessionStatus by remember { mutableStateOf("") }
        var testingSession by remember { mutableStateOf(false) }
        AlertDialog(
            onDismissRequest = { showKeyDialog = false },
            title = { Text("Gemini session & NVIDIA keys") },
            text = {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    Text(
                        "Gemini: paste your own cookie JSON. Cookies grant account access; " +
                            "they stay in memory and are cleared when the app closes. " +
                            "Sessions can expire. NVIDIA still uses API keys."
                    )
                    Spacer(Modifier.height(16.dp))
                    val gc = GeminiWebSession.countCookies(gDraft)
                    OutlinedTextField(
                        value = gDraft,
                        keyboardOptions = KeyboardOptions(autoCorrect = false, keyboardType = KeyboardType.Password),
                        onValueChange = { gDraft = it },
                        label = { Text("Gemini cookie session JSON") },
                        supportingText = {
                            Text(
                                if (gc == 0) "Playwright storageState or cookie-export JSON"
                                else "$gc cookies detected (not yet verified)"
                            )
                        },
                        singleLine = false,
                        minLines = 2,
                        maxLines = 5,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    TextButton(enabled = !testingSession, onClick = {
                        testingSession = true
                        sessionStatus = "Testing session..."
                        scope.launch {
                            sessionStatus = try {
                                GeminiWeb(gDraft).generate("Reply with the single word OK.")
                                "Session alive: Gemini returned a readable reply."
                            } catch (e: GeminiWebException) { e.message ?: "Session test failed." }
                            catch (_: Exception) { "Invalid session JSON or connection failed." }
                            finally { testingSession = false }
                        }
                    }) { Text("Test Gemini session") }
                    if (sessionStatus.isNotBlank()) Text(sessionStatus)
                    Spacer(Modifier.height(14.dp))
                    val nc = KeyPool.parse(nDraft).size
                    OutlinedTextField(
                        value = nDraft,
                        onValueChange = { nDraft = it },
                        label = { Text("NVIDIA keys (nvapi-...)") },
                        supportingText = {
                            Text(
                                if (nc == 0) "From build.nvidia.com"
                                else "$nc key${if (nc == 1) "" else "s"} detected"
                            )
                        },
                        singleLine = false,
                        minLines = 2,
                        maxLines = 5,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            },
            confirmButton = {
                Button(onClick = {
                    try {
                        if (gDraft.isNotBlank()) GeminiWebSession.parse(gDraft)
                    } catch (_: Exception) {
                        sessionStatus = "Invalid Gemini cookie JSON. Check your signed-in session export."
                        return@Button
                    }
                    apiKey = gDraft.trim()
                    nvKey = KeyPool.parse(nDraft).joinToString("\n")
                    save()
                    showKeyDialog = false
                }) { Text("Save") }
            },
            dismissButton = {
                TextButton(onClick = { showKeyDialog = false }) { Text("Cancel") }
            },
        )
    }

    val drawer = rememberDrawerState(DrawerValue.Closed)
    val keyCount = if (provider == Providers.GEMINI) { if (activeKeys.isBlank()) 0 else 1 }
        else KeyPool.parse(activeKeys).size

    ModalNavigationDrawer(
        drawerState = drawer,
        drawerContent = {
            ModalDrawerSheet(drawerContainerColor = Color.White) {
                Column(Modifier.padding(horizontal = 12.dp, vertical = 18.dp)) {
                    Row(
                        Modifier.padding(horizontal = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(
                            Modifier
                                .size(34.dp)
                                .clip(RoundedCornerShape(10.dp))
                                .background(VIOLET),
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(
                                Icons.Filled.AutoStories,
                                contentDescription = null,
                                tint = Color.White,
                                modifier = Modifier.size(18.dp),
                            )
                        }
                        Spacer(Modifier.width(10.dp))
                        Column {
                            Text(
                                APP_NAME,
                                fontWeight = FontWeight.ExtraBold,
                                color = INK,
                            )
                            Text(TAGLINE, fontSize = 11.sp, color = MUTED_INK)
                        }
                    }
                    Spacer(Modifier.height(18.dp))
                    Button(
                        onClick = {
                            scope.launch { drawer.close() }
                            result = null
                            batchZip = null
                        },
                        enabled = !busy,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 8.dp),
                    ) {
                        Icon(
                            Icons.Filled.Add,
                            contentDescription = null,
                            modifier = Modifier.size(18.dp),
                        )
                        Spacer(Modifier.width(8.dp))
                        Text("Create book")
                    }
                    Spacer(Modifier.height(18.dp))
                    DrawerSection("WORKSPACE")
                    NavigationDrawerItem(
                        label = { Text("New book") },
                        selected = result == null,
                        icon = { Icon(Icons.Filled.Add, contentDescription = null) },
                        onClick = { scope.launch { drawer.close() } },
                        colors = NavigationDrawerItemDefaults.colors(
                            selectedContainerColor = VIOLET_WASH,
                            selectedTextColor = VIOLET_DARK,
                            selectedIconColor = VIOLET_DARK,
                        ),
                        modifier = Modifier.padding(horizontal = 4.dp),
                    )
                    NavigationDrawerItem(
                        label = { Text("Books") },
                        selected = result != null,
                        icon = { Icon(Icons.Filled.AutoStories, contentDescription = null) },
                        badge = {
                            if (results.isNotEmpty()) {
                                Text("${results.size}", color = MUTED_INK, fontSize = 12.sp)
                            }
                        },
                        onClick = { scope.launch { drawer.close() } },
                        colors = NavigationDrawerItemDefaults.colors(
                            selectedContainerColor = VIOLET_WASH,
                            selectedTextColor = VIOLET_DARK,
                            selectedIconColor = VIOLET_DARK,
                        ),
                        modifier = Modifier.padding(horizontal = 4.dp),
                    )
                    Spacer(Modifier.height(10.dp))
                    DrawerSection("PUBLISH")
                    NavigationDrawerItem(
                        label = { Text("Play Books checklist") },
                        selected = false,
                        icon = { Icon(Icons.Filled.Checklist, contentDescription = null) },
                        onClick = {
                            scope.launch {
                                drawer.close()
                                if (result == null) {
                                    snackbar.showSnackbar(
                                        "Generate a book first - the checklist sits under the result.",
                                    )
                                }
                            }
                        },
                        modifier = Modifier.padding(horizontal = 4.dp),
                    )
                    Spacer(Modifier.height(10.dp))
                    DrawerSection("SETTINGS")
                    NavigationDrawerItem(
                        label = { Text("Session & API keys") },
                        selected = false,
                        icon = {
                            Icon(
                                if (activeKeys.isBlank()) Icons.Filled.KeyOff else Icons.Filled.Key,
                                contentDescription = null,
                            )
                        },
                        badge = {
                            if (keyCount > 0) {
                                Text("$keyCount", color = MUTED_INK, fontSize = 12.sp)
                            }
                        },
                        onClick = {
                            scope.launch { drawer.close() }
                            showKeyDialog = true
                        },
                        modifier = Modifier.padding(horizontal = 4.dp),
                    )
                }
            }
        },
    ) {
    Scaffold(
        containerColor = Color.Transparent,
        snackbarHost = { SnackbarHost(snackbar) },
        topBar = {
            CenterAlignedTopAppBar(
                colors = TopAppBarDefaults.centerAlignedTopAppBarColors(
                    containerColor = Color.Transparent,
                ),
                title = {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(APP_NAME, fontWeight = FontWeight.ExtraBold, color = GOLD)
                        Text(
                            TAGLINE,
                            fontSize = 11.sp,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                },
                navigationIcon = {
                    IconButton(onClick = { scope.launch { drawer.open() } }) {
                        Icon(Icons.Filled.Menu, contentDescription = "Menu", tint = INK)
                    }
                },
                actions = {
                    IconButton(onClick = { showKeyDialog = true }, enabled = !busy) {
                        Icon(
                            if (activeKeys.isBlank()) Icons.Filled.KeyOff else Icons.Filled.Key,
                            contentDescription = "Session & API keys",
                        )
                    }
                },
            )
        },
    ) { inner ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(inner)
                .padding(horizontal = 16.dp)
                .verticalScroll(rememberScrollState()),
        ) {
            OutlinedTextField(
                value = topic,
                onValueChange = { topic = it },
                label = {
                    Text(
                        if (topics.size > 1) "Book topics (${topics.size} books queued)"
                        else "Book topic"
                    )
                },
                placeholder = { Text("a cozy mystery set in a Cornish fishing village") },
                supportingText = {
                    Text("One topic per line - every line becomes its own full book")
                },
                minLines = 3,
                maxLines = 8,
                enabled = !busy,
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(4.dp))

            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                SegmentedButton(
                    selected = fiction,
                    onClick = { if (!busy) fiction = true },
                    shape = SegmentedButtonDefaults.itemShape(0, 2),
                ) { Text("Fiction") }
                SegmentedButton(
                    selected = !fiction,
                    onClick = { if (!busy) fiction = false },
                    shape = SegmentedButtonDefaults.itemShape(1, 2),
                ) { Text("Non-fiction") }
            }
            Spacer(Modifier.height(12.dp))

            Row {
                OutlinedTextField(
                    value = chapters,
                    onValueChange = { chapters = it.filter(Char::isDigit) },
                    label = { Text("Chapters") },
                    singleLine = true,
                    enabled = !busy,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier = Modifier.weight(1f),
                )
                Spacer(Modifier.width(12.dp))
                OutlinedTextField(
                    value = words,
                    onValueChange = {
                        words = it.filter(Char::isDigit)
                        val w = words.toIntOrNull()
                        if (w != null && w > 0) {
                            pages = Math.round(w / WORDS_PER_PAGE.toFloat()).coerceAtLeast(1).toString()
                        }
                    },
                    label = { Text("Total words") },
                    supportingText = { Text("Linked to pages") },
                    singleLine = true,
                    enabled = !busy,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier = Modifier.weight(1f),
                )
            }
            Spacer(Modifier.height(12.dp))
            OutlinedTextField(
                value = pages,
                onValueChange = {
                    pages = it.filter(Char::isDigit)
                    val pg = pages.toIntOrNull()
                    if (pg != null && pg > 0) words = (pg * WORDS_PER_PAGE).toString()
                },
                label = { Text("Pages (approx.)") },
                supportingText = {
                    Text("About $WORDS_PER_PAGE words per page. Changing this updates the word count.")
                },
                singleLine = true,
                enabled = !busy,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(12.dp))

            OutlinedTextField(
                value = author,
                onValueChange = { author = it },
                label = { Text("Author name") },
                supportingText = { Text("Keep this identical across all your books") },
                singleLine = true,
                enabled = !busy,
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(12.dp))

            Dropdown(
                label = "Provider",
                value = Providers.label(provider),
                options = Providers.ALL.map { Providers.label(it) },
                enabled = !busy,
                modifier = Modifier.fillMaxWidth(),
            ) { picked ->
                provider = Providers.ALL.first { Providers.label(it) == picked }
                model = Providers.fixModel(provider, model)
                coverArt = ImageGen.fixModel(provider, coverArt)
            }
            Spacer(Modifier.height(12.dp))

            Row {
                Dropdown(
                    label = "Model",
                    value = Providers.fixModel(provider, model),
                    options = Providers.models(provider),
                    enabled = !busy,
                    modifier = Modifier.weight(1f),
                ) { model = it }
                Spacer(Modifier.width(12.dp))
                Dropdown(
                    label = "Cover theme",
                    value = theme,
                    options = listOf("auto") + CoverTheme.ALL.keys,
                    enabled = !busy,
                    modifier = Modifier.weight(1f),
                ) { theme = it }
            }
            Spacer(Modifier.height(12.dp))

            Dropdown(
                label = "Cover art (AI image)",
                value = ImageGen.label(ImageGen.fixModel(provider, coverArt)),
                options = ImageGen.modelsFor(provider).map { ImageGen.label(it) },
                enabled = !busy,
                modifier = Modifier.fillMaxWidth(),
            ) { picked ->
                coverArt = ImageGen.modelsFor(provider).first { ImageGen.label(it) == picked }
            }
            Spacer(Modifier.height(12.dp))

            OutlinedTextField(
                value = note,
                onValueChange = { note = it },
                label = { Text("Extra instructions (optional)") },
                placeholder = { Text("set in 1920s Dhaka, first person") },
                singleLine = true,
                enabled = !busy,
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(10.dp))

            TextButton(
                onClick = { showExtras = !showExtras },
                enabled = !busy,
            ) {
                Text(
                    if (showExtras) "Hide front & back matter"
                    else "Front & back matter (copyright, bio, also-by)",
                    color = GOLD,
                )
            }
            if (showExtras) {
                OutlinedTextField(
                    value = bio,
                    onValueChange = { bio = it },
                    label = { Text("About the author") },
                    supportingText = { Text("Leave empty to use the bio the planner writes") },
                    minLines = 2,
                    maxLines = 4,
                    enabled = !busy,
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(Modifier.height(12.dp))
                OutlinedTextField(
                    value = alsoBy,
                    onValueChange = { alsoBy = it },
                    label = { Text("Also by you") },
                    supportingText = { Text("One title per line - sells your back catalogue") },
                    minLines = 2,
                    maxLines = 5,
                    enabled = !busy,
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(Modifier.height(12.dp))
                OutlinedTextField(
                    value = publisher,
                    onValueChange = { publisher = it },
                    label = { Text("Publisher / imprint (optional)") },
                    supportingText = { Text("Defaults to your author name") },
                    singleLine = true,
                    enabled = !busy,
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(Modifier.height(12.dp))
                OutlinedTextField(
                    value = newsletter,
                    onValueChange = { newsletter = it },
                    label = { Text("Stay in touch page (optional)") },
                    placeholder = { Text("Follow me on Google Play, or email ...") },
                    minLines = 1,
                    maxLines = 3,
                    enabled = !busy,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            Spacer(Modifier.height(20.dp))

            Button(
                onClick = { start() },
                enabled = !busy,
                modifier = Modifier.fillMaxWidth(),
                contentPadding = PaddingValues(vertical = 14.dp),
            ) {
                Icon(Icons.Filled.AutoStories, contentDescription = null)
                Spacer(Modifier.width(10.dp))
                Text(
                    when {
                        busy && bookTotal > 1 -> "Writing book $bookIndex of $bookTotal..."
                        busy -> "Writing..."
                        topics.size > 1 -> "Generate ${topics.size} books"
                        else -> "Generate book"
                    }
                )
            }

            if (busy) {
                Spacer(Modifier.height(8.dp))
                LinearProgressIndicator(
                    progress = { progress },
                    modifier = Modifier.fillMaxWidth(),
                )
                TextButton(onClick = {
                    writer?.cancel()
                    log.add("Cancelling after the current step...")
                }, modifier = Modifier.align(Alignment.CenterHorizontally)) {
                    Icon(Icons.Filled.StopCircle, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text("Cancel")
                }
            }

            batchZip?.let { z ->
                Spacer(Modifier.height(16.dp))
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(14.dp)) {
                        Text(
                            "${results.size} books finished - one archive with every " +
                                "EPUB, cover and upload sheet.",
                            style = MaterialTheme.typography.bodySmall,
                        )
                        Spacer(Modifier.height(10.dp))
                        Button(
                            onClick = {
                                zipToSave = z
                                saveZipLauncher.launch(z.name)
                            },
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Icon(Icons.Filled.Download, contentDescription = null)
                            Spacer(Modifier.width(8.dp))
                            Text("Download all books (ZIP)")
                        }
                        Spacer(Modifier.height(8.dp))
                        FilledTonalButton(
                            onClick = { shareFile(context, z) },
                            modifier = Modifier.fillMaxWidth(),
                        ) { Text("Share batch ZIP") }
                    }
                }
            }

            results.asReversed().forEach { b ->
                Spacer(Modifier.height(16.dp))
                ResultCard(
                    r = b,
                    onShare = { file -> shareFile(context, file) },
                    onSaveZip = {
                        zipToSave = b.zip
                        saveZipLauncher.launch(b.zip.name)
                    },
                )
                Spacer(Modifier.height(8.dp))
                Row {
                    FilledTonalButton(
                        onClick = { studioFor = b },
                        enabled = !busy,
                        modifier = Modifier.weight(1f),
                    ) { Text("Cover studio") }
                    Spacer(Modifier.width(8.dp))
                    FilledTonalButton(
                        onClick = { postJob(b) { w, p -> w.qualityPass(b, p) } },
                        enabled = !busy,
                        modifier = Modifier.weight(1f),
                    ) { Text(if (b.report == null) "Editor pass" else "Editor again") }
                }
                if (b.request.coverArtModel != ImageGen.OFF) {
                    Spacer(Modifier.height(8.dp))
                    OutlinedButton(
                        onClick = { postJob(b) { w, p -> w.regenerateArtwork(b, p) } },
                        enabled = !busy,
                        modifier = Modifier.fillMaxWidth(),
                    ) { Text("New artwork") }
                }
                b.report?.let { rep ->
                    Spacer(Modifier.height(10.dp))
                    QualityCard(report = rep, busy = busy) { idx, nt ->
                        rewriteFor = b
                        rewriteIndex = idx
                        rewriteNote = nt
                    }
                }
                Spacer(Modifier.height(4.dp))
                val key = b.directory.path
                TextButton(onClick = {
                    expandedChapters = if (expandedChapters == key) null else key
                }) {
                    Text(
                        if (expandedChapters == key) "Hide chapters"
                        else "Chapters (${b.chapters.size})",
                        color = GOLD,
                    )
                }
                if (expandedChapters == key) {
                    b.chapters.forEachIndexed { i, c ->
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(
                                    "${i + 1}. ${c.title}",
                                    style = MaterialTheme.typography.bodySmall,
                                )
                                Text(
                                    "${c.words} words",
                                    style = MaterialTheme.typography.labelSmall,
                                )
                            }
                            TextButton(
                                onClick = {
                                    rewriteFor = b
                                    rewriteIndex = i
                                    rewriteNote = ""
                                },
                                enabled = !busy,
                            ) { Text("Rewrite") }
                        }
                    }
                }
            }

            result?.let { r ->
                Spacer(Modifier.height(12.dp))
                PublishChecklist(
                    fields = PublishFields.build(
                        r.plan, r.words, r.plan.chapters.size, r.epub.name,
                        r.request.extras.publisher,
                    ),
                    onCopied = { label ->
                        scope.launch { snackbar.showSnackbar("$label copied.") }
                    },
                )
            }

            if (log.isNotEmpty()) {
                Spacer(Modifier.height(16.dp))
                Card(Modifier.fillMaxWidth()) {
                    LazyColumn(
                        state = listState,
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(260.dp)
                            .padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(3.dp),
                    ) {
                        items(log.toList()) { line ->
                            Text(line, fontFamily = FontFamily.Monospace, fontSize = 12.sp)
                        }
                    }
                }
            }
            Spacer(Modifier.height(24.dp))
        }
    }
    }
}

@Composable
private fun DrawerSection(label: String) {
    Text(
        label,
        fontSize = 11.sp,
        fontWeight = FontWeight.Bold,
        letterSpacing = 0.8.sp,
        color = MUTED_INK,
        modifier = Modifier.padding(start = 16.dp, bottom = 6.dp),
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Dropdown(
    label: String,
    value: String,
    options: Collection<String>,
    enabled: Boolean,
    modifier: Modifier = Modifier,
    onPick: (String) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { if (enabled) expanded = !expanded },
        modifier = modifier,
    ) {
        OutlinedTextField(
            value = value,
            onValueChange = {},
            readOnly = true,
            enabled = enabled,
            label = { Text(label) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier
                .fillMaxWidth()
                .menuAnchor(androidx.compose.material3.MenuAnchorType.PrimaryNotEditable),
        )
        ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            options.forEach { option ->
                DropdownMenuItem(
                    text = { Text(option) },
                    onClick = { onPick(option); expanded = false },
                )
            }
        }
    }
}

@Composable
private fun ResultCard(
    r: BookResult,
    onShare: (File) -> Unit,
    onSaveZip: () -> Unit,
) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                val bmp = remember(r.cover.path) {
                    BitmapFactory.decodeFile(r.cover.path)
                }
                if (bmp != null) {
                    Image(
                        bitmap = bmp.asImageBitmap(),
                        contentDescription = "Cover",
                        modifier = Modifier
                            .size(width = 80.dp, height = 128.dp)
                            .clip(RoundedCornerShape(6.dp)),
                    )
                    Spacer(Modifier.width(16.dp))
                }
                Column(Modifier.weight(1f)) {
                    Text(
                        r.plan.title,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                    )
                    if (r.plan.series.isNotEmpty()) {
                        Text(r.plan.series, style = MaterialTheme.typography.labelSmall)
                    }
                    Spacer(Modifier.height(6.dp))
                    Text(
                        "${r.words} words  -  ${r.plan.chapters.size} chapters  -  " +
                            "USD %.2f".format(r.plan.priceUsd),
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
            Spacer(Modifier.height(12.dp))
            Button(onClick = onSaveZip, modifier = Modifier.fillMaxWidth()) {
                Icon(Icons.Filled.Download, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("Download ZIP (everything)")
            }
            Spacer(Modifier.height(8.dp))
            Row {
                FilledTonalButton(onClick = { onShare(r.epub) }) {
                    Icon(Icons.Filled.Share, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text("Share EPUB")
                }
                Spacer(Modifier.width(8.dp))
                FilledTonalButton(onClick = { onShare(r.zip) }) {
                    Text("Share ZIP")
                }
            }
        }
    }
}

@Composable
private fun PublishChecklist(fields: List<PublishField>, onCopied: (String) -> Unit) {
    val clipboard = LocalClipboardManager.current
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Checklist, contentDescription = null, tint = GOLD)
                Spacer(Modifier.width(8.dp))
                Text(
                    "Everything you need to publish",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold,
                    color = GOLD,
                )
            }
            Spacer(Modifier.height(10.dp))
            PublishFields.STEPS.forEachIndexed { i, step ->
                Row(Modifier.padding(bottom = 4.dp)) {
                    Text(
                        "${i + 1}.",
                        modifier = Modifier.width(22.dp),
                        style = MaterialTheme.typography.bodySmall,
                        fontWeight = FontWeight.Bold,
                        color = GOLD,
                    )
                    Text(step, style = MaterialTheme.typography.bodySmall)
                }
            }
            for (group in PublishFields.GROUPS) {
                val rows = fields.filter { it.group == group }
                if (rows.isEmpty()) continue
                Spacer(Modifier.height(14.dp))
                Text(
                    group.uppercase(),
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 1.6.sp,
                    color = VIOLET,
                )
                Spacer(Modifier.height(6.dp))
                rows.forEach { field ->
                    Row(
                        Modifier.padding(bottom = 10.dp),
                        verticalAlignment = Alignment.Top,
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text(
                                field.label,
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Text(
                                field.value,
                                style = MaterialTheme.typography.bodyMedium,
                                fontWeight = FontWeight.SemiBold,
                            )
                            if (field.hint.isNotEmpty()) {
                                Text(
                                    field.hint,
                                    style = MaterialTheme.typography.bodySmall,
                                    fontStyle = FontStyle.Italic,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                        IconButton(onClick = {
                            clipboard.setText(AnnotatedString(field.value))
                            onCopied(field.label)
                        }) {
                            Icon(
                                Icons.Filled.ContentCopy,
                                contentDescription = "Copy ${field.label}",
                                tint = GOLD,
                            )
                        }
                    }
                }
            }
        }
    }
}

private fun shareFile(context: Context, file: File) {
    val uri = FileProvider.getUriForFile(
        context,
        "${context.packageName}.fileprovider",
        file,
    )
    val mime = when (file.extension.lowercase()) {
        "zip" -> "application/zip"
        "epub" -> "application/epub+zip"
        "png" -> "image/png"
        else -> "text/plain"
    }
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = mime
        putExtra(Intent.EXTRA_STREAM, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(Intent.createChooser(intent, "Share ${file.name}"))
}
