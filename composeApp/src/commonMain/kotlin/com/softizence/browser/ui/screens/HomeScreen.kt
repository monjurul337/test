package com.softizence.browser.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.softizence.browser.net.NetworkMode
import com.softizence.browser.ui.theme.LocalSoftizenceColors
import com.softizence.browser.ui.theme.Obsidian

/**
 * `softizence://home`. Deliberately quiet: a wordmark, the live network truth, and
 * the user's own shortcuts. No sponsored tiles, no news feed, no telemetry.
 */
@Composable
fun HomeScreen(
    mode: NetworkMode,
    publicIp: String?,
    shortcuts: List<Shortcut>,
    onOpen: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalSoftizenceColors.current
    Box(
        modifier
            .fillMaxSize()
            .background(
                Brush.radialGradient(
                    colors = listOf(Color(0xFF14161D), Obsidian.Ink),
                    radius = 1400f,
                ),
            ),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.widthIn(max = 720.dp).padding(32.dp),
        ) {
            Text(
                "SOFTIZENCE",
                style = MaterialTheme.typography.displaySmall.copy(
                    fontWeight = FontWeight.Light,
                    letterSpacing = 10.sp,
                ),
                color = Obsidian.Porcelain,
            )
            Spacer(Modifier.height(6.dp))
            Box(
                Modifier
                    .width(120.dp)
                    .height(1.dp)
                    .background(Brush.horizontalGradient(listOf(Color.Transparent, colors.accent, Color.Transparent))),
            )
            Spacer(Modifier.height(18.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    when (mode) {
                        NetworkMode.Tunnelled -> "Tunnelled"
                        NetworkMode.Direct -> "Direct connection"
                        NetworkMode.Blocked -> "Blocked — tunnel down"
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = when (mode) {
                        NetworkMode.Tunnelled -> colors.tunnelUp
                        NetworkMode.Blocked -> colors.tunnelBlocked
                        NetworkMode.Direct -> colors.muted
                    },
                )
                if (publicIp != null) {
                    Text(
                        "  ·  $publicIp",
                        style = MaterialTheme.typography.bodySmall,
                        fontFamily = FontFamily.Monospace,
                        color = colors.muted,
                    )
                }
            }

            Spacer(Modifier.height(40.dp))
            LazyVerticalGrid(
                columns = GridCells.Adaptive(minSize = 132.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                items(shortcuts) { shortcut ->
                    Column(
                        Modifier
                            .clip(MaterialTheme.shapes.medium)
                            .background(MaterialTheme.colorScheme.surface)
                            .clickable { onOpen(shortcut.url) }
                            .padding(16.dp),
                    ) {
                        Box(
                            Modifier
                                .size(26.dp)
                                .clip(MaterialTheme.shapes.extraSmall)
                                .background(colors.accentSoft),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                shortcut.title.take(1).uppercase(),
                                style = MaterialTheme.typography.titleMedium,
                                color = colors.accent,
                            )
                        }
                        Spacer(Modifier.height(10.dp))
                        Text(shortcut.title, style = MaterialTheme.typography.titleMedium, maxLines = 1)
                        Text(
                            shortcut.url.substringAfter("://").substringBefore('/'),
                            style = MaterialTheme.typography.bodySmall,
                            color = colors.muted,
                            maxLines = 1,
                        )
                    }
                }
            }
        }
    }
}

data class Shortcut(val title: String, val url: String)
