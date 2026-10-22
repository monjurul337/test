package com.softizence.browser

import androidx.compose.runtime.remember
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.application
import androidx.compose.ui.window.rememberWindowState
import com.softizence.browser.browser.CefBrowserEngine
import com.softizence.browser.di.AppGraph
import com.softizence.browser.extensions.DesktopExtensionHost
import com.softizence.browser.net.ImportedFile
import com.softizence.browser.ui.SoftizenceApp
import java.awt.FileDialog
import java.awt.Frame
import javax.swing.JFileChooser

fun main() = application {
    val graph = remember { AppGraph.create() }

    // Let the CEF engine see the extension host before Chromium starts.
    (graph.engine as? CefBrowserEngine)?.extensionHost = graph.extensionHost as? DesktopExtensionHost

    graph.onPickConfigs = {
        val dialog = FileDialog(null as Frame?, "Import WireGuard configuration", FileDialog.LOAD).apply {
            isMultipleMode = true
            setFilenameFilter { _, name -> name.endsWith(".conf") }
            isVisible = true
        }
        val files = dialog.files.orEmpty().map { ImportedFile(it.name, it.readText()) }
        if (files.isNotEmpty()) graph.viewModel.importConfigs(files)
    }

    graph.onPickExtensionFolder = {
        val chooser = JFileChooser().apply {
            fileSelectionMode = JFileChooser.DIRECTORIES_ONLY
            dialogTitle = "Select an unpacked MV3 extension folder"
        }
        if (chooser.showOpenDialog(null) == JFileChooser.APPROVE_OPTION) {
            graph.viewModel.loadExtension(chooser.selectedFile.absolutePath)
        }
    }

    graph.viewModel.start()

    Window(
        onCloseRequest = {
            graph.viewModel.persist()
            graph.shutdown()
            exitApplication()
        },
        title = "Softizence",
        state = rememberWindowState(size = DpSize(1320.dp, 860.dp)),
    ) {
        SoftizenceApp(graph.viewModel)
    }
}
