package com.softizence.browser.ui.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Shield
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.softizence.browser.core.model.TabState
import com.softizence.browser.ui.theme.LocalSoftizenceColors

/**
 * Desktop signature surface: a vertical brass-lit rail instead of the usual cramped
 * horizontal tab strip. Titles stay readable at 30 tabs, and the active tab is marked by
 * a glowing edge rather than a boxy "selected" chip.
 */
@Composable
fun TabRail(
    tabs: List<TabState>,
    activeTabId: String?,
    onSelect: (String) -> Unit,
    onClose: (String) -> Unit,
    onNewTab: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalSoftizenceColors.current
    Column(
        modifier = modifier
            .fillMaxHeight()
            .width(244.dp)
            .background(MaterialTheme.colorScheme.surface)
            .padding(vertical = 10.dp),
    ) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                "TABS",
                style = MaterialTheme.typography.labelSmall,
                color = colors.muted,
                modifier = Modifier.weight(1f),
            )
            IconButton(onClick = onNewTab, modifier = Modifier.size(28.dp)) {
                Icon(Icons.Rounded.Add, "New tab", tint = colors.accent, modifier = Modifier.size(18.dp))
            }
        }
        LazyColumn(
            verticalArrangement = Arrangement.spacedBy(2.dp),
            modifier = Modifier.weight(1f).padding(horizontal = 8.dp),
        ) {
            items(tabs, key = { it.id }) { tab ->
                TabRailItem(
                    tab = tab,
                    selected = tab.id == activeTabId,
                    onSelect = { onSelect(tab.id) },
                    onClose = { onClose(tab.id) },
                )
            }
        }
    }
}

@Composable
private fun TabRailItem(
    tab: TabState,
    selected: Boolean,
    onSelect: () -> Unit,
    onClose: () -> Unit,
) {
    val colors = LocalSoftizenceColors.current
    val bg by animateColorAsState(
        if (selected) MaterialTheme.colorScheme.surfaceVariant else androidx.compose.ui.graphics.Color.Transparent,
        label = "tabBg",
    )
    val glowHeight by animateDpAsState(if (selected) 26.dp else 0.dp, label = "tabGlow")

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(MaterialTheme.shapes.small)
            .background(bg)
            .clickable(onClick = onSelect)
            .padding(start = 4.dp, end = 6.dp, top = 7.dp, bottom = 7.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .width(3.dp)
                .height(glowHeight)
                .clip(RoundedCornerShape(2.dp))
                .background(colors.railGlow),
        )
        Spacer(Modifier.width(9.dp))
        if (tab.isIncognito) {
            Icon(Icons.Rounded.Shield, null, tint = colors.accent, modifier = Modifier.size(13.dp))
            Spacer(Modifier.width(6.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(
                text = tab.title.ifBlank { "Untitled" },
                style = MaterialTheme.typography.bodySmall,
                color = if (selected) MaterialTheme.colorScheme.onSurface else colors.muted,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (tab.isLoading) {
                Spacer(Modifier.height(4.dp))
                Box(
                    Modifier
                        .fillMaxWidth(tab.progress.coerceIn(0.05f, 1f))
                        .height(1.5.dp)
                        .background(colors.accent),
                )
            }
        }
        IconButton(onClick = onClose, modifier = Modifier.size(22.dp)) {
            Icon(Icons.Rounded.Close, "Close tab", tint = colors.muted, modifier = Modifier.size(13.dp))
        }
    }
}
