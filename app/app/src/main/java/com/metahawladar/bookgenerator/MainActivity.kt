package com.metahawladar.bookgenerator

import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Bundle
import android.os.Environment
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.Image
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
import androidx.compose.material.icons.filled.AutoStories
import androidx.compose.material.icons.filled.Key
import androidx.compose.material.icons.filled.KeyOff
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
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

const val APP_NAME = "Book Generator"
const val TAGLINE = "Meta Hawladar Team"
private const val PREFS = "book_generator"

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            MaterialTheme(
                colorScheme = darkColorScheme(
                    primary = Color(0xFF818CF8),
                    secondary = Color(0xFF22D3EE),
                    surface = Color(0xFF1F2937),
                    background = Color(0xFF111827),
                )
            ) {
                HomeScreen()
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

    var apiKey by remember { mutableStateOf(prefs.getString("apiKey", "") ?: "") }
    var author by remember {
        mutableStateOf(prefs.getString("author", "Md Monjurul Islam") ?: "Md Monjurul Islam")
    }
    var model by remember { mutableStateOf(prefs.getString("model", Gemini.MODELS[0]) ?: Gemini.MODELS[0]) }
    var topic by remember { mutableStateOf("") }
    var note by remember { mutableStateOf("") }
    var chapters by remember { mutableStateOf("16") }
    var words by remember { mutableStateOf("15000") }
    var fiction by remember { mutableStateOf(true) }
    var theme by remember { mutableStateOf("auto") }
    var busy by remember { mutableStateOf(false) }
    var progress by remember { mutableStateOf(0f) }
    var result by remember { mutableStateOf<BookResult?>(null) }
    var showKeyDialog by remember { mutableStateOf(false) }
    val log = remember { androidx.compose.runtime.mutableStateListOf<String>() }
    var writer by remember { mutableStateOf<BookWriter?>(null) }
    val listState = rememberLazyListState()

    LaunchedEffect(log.size) {
        if (log.isNotEmpty()) listState.animateScrollToItem(log.size - 1)
    }

    fun save() {
        prefs.edit()
            .putString("apiKey", apiKey)
            .putString("author", author)
            .putString("model", model)
            .apply()
    }

    fun start() {
        if (topic.isBlank()) {
            scope.launch { snackbar.showSnackbar("Type a topic first.") }
            return
        }
        if (apiKey.isBlank()) { showKeyDialog = true; return }
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
        log.clear()
        val w = BookWriter(apiKey, outputRoot(context))
        writer = w
        scope.launch {
            try {
                val r = withContext(Dispatchers.IO) {
                    w.run(
                        BookRequest(
                            topic = topic.trim(),
                            author = author.trim().ifBlank { "Anonymous" },
                            fiction = fiction,
                            chapters = nChapters,
                            totalWords = nWords,
                            model = model,
                            themeOverride = if (theme == "auto") null else theme,
                            note = note.trim(),
                        )
                    ) { f, m ->
                        progress = f
                        log.add(m)
                        if (log.size > 400) log.removeAt(0)
                    }
                }
                result = r
            } catch (e: Exception) {
                log.add("ERROR: ${e.message}")
                snackbar.showSnackbar(e.message ?: "Failed")
            } finally {
                busy = false
                writer = null
            }
        }
    }

    if (showKeyDialog) {
        var draft by remember { mutableStateOf(apiKey) }
        AlertDialog(
            onDismissRequest = { showKeyDialog = false },
            title = { Text("Gemini API key") },
            text = {
                Column {
                    Text(
                        "Create a free key at aistudio.google.com/apikey and paste it here. " +
                            "It is stored only on this device."
                    )
                    Spacer(Modifier.height(16.dp))
                    OutlinedTextField(
                        value = draft,
                        onValueChange = { draft = it },
                        label = { Text("API key") },
                        singleLine = true,
                        visualTransformation = PasswordVisualTransformation(),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            },
            confirmButton = {
                Button(onClick = {
                    apiKey = draft.trim()
                    save()
                    showKeyDialog = false
                }) { Text("Save") }
            },
            dismissButton = {
                TextButton(onClick = { showKeyDialog = false }) { Text("Cancel") }
            },
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbar) },
        topBar = {
            CenterAlignedTopAppBar(
                title = {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(APP_NAME, fontWeight = FontWeight.Bold)
                        Text(
                            TAGLINE,
                            fontSize = 11.sp,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                },
                actions = {
                    IconButton(onClick = { showKeyDialog = true }, enabled = !busy) {
                        Icon(
                            if (apiKey.isBlank()) Icons.Filled.KeyOff else Icons.Filled.Key,
                            contentDescription = "API key",
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
                label = { Text("Book topic") },
                placeholder = { Text("a cozy mystery set in a Cornish fishing village") },
                minLines = 2,
                enabled = !busy,
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(12.dp))

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
                    onValueChange = { words = it.filter(Char::isDigit) },
                    label = { Text("Total words") },
                    singleLine = true,
                    enabled = !busy,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier = Modifier.weight(1f),
                )
            }
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

            Row {
                Dropdown(
                    label = "Model",
                    value = model,
                    options = Gemini.MODELS,
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

            OutlinedTextField(
                value = note,
                onValueChange = { note = it },
                label = { Text("Extra instructions (optional)") },
                placeholder = { Text("set in 1920s Dhaka, first person") },
                singleLine = true,
                enabled = !busy,
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(20.dp))

            Button(
                onClick = { start() },
                enabled = !busy,
                modifier = Modifier.fillMaxWidth(),
                contentPadding = PaddingValues(vertical = 14.dp),
            ) {
                Icon(Icons.Filled.AutoStories, contentDescription = null)
                Spacer(Modifier.width(10.dp))
                Text(if (busy) "Writing..." else "Generate book")
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

            result?.let { r ->
                Spacer(Modifier.height(16.dp))
                ResultCard(r) { file -> shareFile(context, file) }
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
private fun ResultCard(r: BookResult, onShare: (File) -> Unit) {
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
            Row {
                FilledTonalButton(onClick = { onShare(r.epub) }) {
                    Icon(Icons.Filled.Share, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text("Share EPUB")
                }
                Spacer(Modifier.width(8.dp))
                FilledTonalButton(onClick = { onShare(r.metadata) }) {
                    Text("Share metadata")
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
