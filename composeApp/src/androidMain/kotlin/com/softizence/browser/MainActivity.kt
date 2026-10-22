package com.softizence.browser

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.lifecycle.lifecycleScope
import com.softizence.browser.net.AndroidTunnelController
import com.softizence.browser.net.ImportedFile
import com.softizence.browser.ui.SoftizenceApp
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    private var vpnConsent: CompletableDeferred<Boolean>? = null

    private val vpnPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            vpnConsent?.complete(result.resultCode == Activity.RESULT_OK)
        }

    /** Multi-select `.conf` importer wired to the Tunnels panel. */
    private val confPicker =
        registerForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
            if (uris.isEmpty()) return@registerForActivityResult
            lifecycleScope.launch {
                val files = uris.mapNotNull { uri ->
                    val name = contentResolver.query(uri, null, null, null, null)?.use { c ->
                        val index = c.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                        if (c.moveToFirst() && index >= 0) c.getString(index) else null
                    } ?: "tunnel.conf"
                    contentResolver.openInputStream(uri)?.use { ImportedFile(name, it.readBytes().decodeToString()) }
                }
                graph.viewModel.importConfigs(files)
            }
        }

    private val graph by lazy { (application as SoftizenceApplication).graph }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        (graph.tunnelController as? AndroidTunnelController)?.attachPermissionLauncher { intent ->
            val deferred = CompletableDeferred<Boolean>()
            vpnConsent = deferred
            vpnPermissionLauncher.launch(intent)
            deferred.await()
        }
        graph.onPickConfigs = { confPicker.launch(arrayOf("*/*")) }
        graph.viewModel.start()

        // Handle "open link in Softizence".
        intent?.takeIf { it.action == Intent.ACTION_VIEW }?.dataString
            ?.let { graph.viewModel.navigate(it) }

        setContent { SoftizenceApp(graph.viewModel) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == Intent.ACTION_VIEW) intent.dataString?.let { graph.viewModel.navigate(it) }
    }

    override fun onStop() {
        super.onStop()
        graph.viewModel.persist()
    }
}
