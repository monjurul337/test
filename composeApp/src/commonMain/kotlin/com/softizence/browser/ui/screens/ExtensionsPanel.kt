package com.softizence.browser.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Extension
import androidx.compose.material.icons.rounded.FolderOpen
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.softizence.browser.core.model.ExtensionInfo
import com.softizence.browser.extensions.ExtensionCapabilities
import com.softizence.browser.ui.theme.LocalSoftizenceColors

@Composable
fun ExtensionsPanel(
    extensions: List<ExtensionInfo>,
    capabilities: ExtensionCapabilities,
    onLoadFolder: () -> Unit,
    onToggle: (String, Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalSoftizenceColors.current
    Column(
        modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surface).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Extensions", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.weight(1f))
            TextButton(onClick = onLoadFolder) {
                Icon(Icons.Rounded.FolderOpen, null, modifier = Modifier.size(16.dp))
                Spacer(Modifier.size(6.dp))
                Text("Load unpacked")
            }
        }

        if (!capabilities.serviceWorkers) {
            Row(
                Modifier
                    .fillMaxWidth()
                    .clip(MaterialTheme.shapes.medium)
                    .background(colors.accentSoft)
                    .padding(12.dp),
                verticalAlignment = Alignment.Top,
            ) {
                Icon(Icons.Rounded.Warning, null, tint = colors.accent, modifier = Modifier.size(16.dp))
                Spacer(Modifier.size(10.dp))
                Text(
                    "This platform runs the MV3 subset: content scripts and declarativeNetRequest " +
                        "rules are honoured, but background service workers and chrome.* APIs are not. " +
                        "Full MV3 hosting runs on Desktop.",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }

        if (extensions.isEmpty()) {
            Text(
                "No extensions loaded. Point Softizence at an unpacked MV3 folder " +
                    "(the one containing manifest.json).",
                style = MaterialTheme.typography.bodySmall,
                color = colors.muted,
            )
        }

        LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(extensions, key = { it.id }) { ext ->
                Row(
                    Modifier
                        .fillMaxWidth()
                        .clip(MaterialTheme.shapes.medium)
                        .background(MaterialTheme.colorScheme.surfaceVariant)
                        .padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Rounded.Extension, null, tint = colors.accent, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.size(10.dp))
                    Column(Modifier.weight(1f)) {
                        Text("${ext.name}  ${ext.version}", style = MaterialTheme.typography.titleMedium)
                        Text(
                            ext.loadError ?: ext.description.ifBlank {
                                ext.permissions.take(4).joinToString(", ").ifBlank { "No permissions requested" }
                            },
                            style = MaterialTheme.typography.bodySmall,
                            color = if (ext.loadError != null) colors.tunnelBlocked else colors.muted,
                            maxLines = 2,
                        )
                    }
                    Switch(
                        checked = ext.enabled,
                        enabled = ext.loadError == null,
                        onCheckedChange = { onToggle(ext.id, it) },
                    )
                }
            }
        }
    }
}
