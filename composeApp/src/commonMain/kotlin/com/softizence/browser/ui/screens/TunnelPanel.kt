package com.softizence.browser.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Bolt
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.FileUpload
import androidx.compose.material.icons.rounded.PowerSettingsNew
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.softizence.browser.core.model.TunnelState
import com.softizence.browser.net.NetworkMode
import com.softizence.browser.net.WireGuardConfig
import com.softizence.browser.ui.components.humanBytes
import com.softizence.browser.ui.theme.LocalSoftizenceColors

/**
 * Tunnel library. Drop Proton `.conf` files here; one tap routes the whole browser
 * through them. With nothing active the app browses direct, and says so plainly.
 */
@Composable
fun TunnelPanel(
    configs: List<WireGuardConfig>,
    state: TunnelState,
    mode: NetworkMode,
    killSwitch: Boolean,
    onImport: () -> Unit,
    onActivate: (String) -> Unit,
    onDeactivate: () -> Unit,
    onRemove: (String) -> Unit,
    onKillSwitchChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalSoftizenceColors.current

    Column(
        modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surface)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Tunnels", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.weight(1f))
            TextButton(onClick = onImport) {
                Icon(Icons.Rounded.FileUpload, null, modifier = Modifier.size(16.dp))
                Spacer(Modifier.size(6.dp))
                Text("Import .conf")
            }
        }

        // Live proof of where traffic exits.
        Column(
            Modifier
                .fillMaxWidth()
                .clip(MaterialTheme.shapes.medium)
                .background(MaterialTheme.colorScheme.surfaceVariant)
                .padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(
                when (mode) {
                    NetworkMode.Tunnelled -> "All traffic is routed through ${state.activeConfigName}"
                    NetworkMode.Direct -> if (configs.isEmpty())
                        "No tunnels imported — browsing directly"
                    else "No tunnel active — browsing directly"
                    NetworkMode.Blocked -> "Traffic is blocked: kill switch is on and the tunnel is down"
                },
                style = MaterialTheme.typography.bodyMedium,
                color = when (mode) {
                    NetworkMode.Tunnelled -> colors.tunnelUp
                    NetworkMode.Blocked -> colors.tunnelBlocked
                    NetworkMode.Direct -> colors.muted
                },
            )
            Text(
                "Public IP  ${state.publicIp ?: "—"}${state.country?.let { "  ·  $it" } ?: ""}",
                style = MaterialTheme.typography.bodySmall,
                fontFamily = FontFamily.Monospace,
            )
            if (state.isUp) {
                Text(
                    "↓ ${state.rxBytes.humanBytes()}   ↑ ${state.txBytes.humanBytes()}   " +
                        "handshake ${state.lastHandshakeEpochSeconds.takeIf { it > 0 }?.let { "ok" } ?: "pending"}",
                    style = MaterialTheme.typography.labelSmall,
                    color = colors.muted,
                )
            }
            state.errorMessage?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = colors.tunnelBlocked)
            }
        }

        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("Kill switch", style = MaterialTheme.typography.titleMedium)
                Text(
                    "Block everything if the tunnel drops",
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.muted,
                )
            }
            Switch(checked = killSwitch, onCheckedChange = onKillSwitchChange)
        }

        if (configs.isEmpty()) {
            Text(
                "Import a Proton VPN WireGuard configuration to begin. " +
                    "Proton: Downloads → WireGuard configuration → pick a server → save the .conf.",
                style = MaterialTheme.typography.bodySmall,
                color = colors.muted,
            )
        }

        LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(configs, key = { it.id }) { cfg ->
                val active = cfg.id == state.activeConfigId
                Row(
                    Modifier
                        .fillMaxWidth()
                        .clip(MaterialTheme.shapes.medium)
                        .background(MaterialTheme.colorScheme.surfaceVariant)
                        .border(
                            1.dp,
                            if (active) colors.tunnelUp.copy(alpha = 0.5f) else colors.hairline,
                            MaterialTheme.shapes.medium,
                        )
                        .clickable { if (active) onDeactivate() else onActivate(cfg.id) }
                        .padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        if (active) Icons.Rounded.Bolt else Icons.Rounded.PowerSettingsNew,
                        null,
                        tint = if (active) colors.tunnelUp else colors.muted,
                        modifier = Modifier.size(18.dp),
                    )
                    Spacer(Modifier.size(10.dp))
                    Column(Modifier.weight(1f)) {
                        Text(cfg.name, style = MaterialTheme.typography.titleMedium)
                        Text(
                            "${cfg.peers.first().label ?: cfg.peers.first().endpointHost} · " +
                                "${cfg.peers.first().endpointHost}:${cfg.peers.first().endpointPort}",
                            style = MaterialTheme.typography.bodySmall,
                            fontFamily = FontFamily.Monospace,
                            color = colors.muted,
                        )
                    }
                    IconButton(onClick = { onRemove(cfg.id) }, modifier = Modifier.size(28.dp)) {
                        Icon(Icons.Rounded.Delete, "Remove", tint = colors.muted, modifier = Modifier.size(16.dp))
                    }
                }
            }
        }
        Spacer(Modifier.height(4.dp))
    }
}
