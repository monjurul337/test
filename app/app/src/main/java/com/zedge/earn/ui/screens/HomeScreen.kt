package com.zedge.earn.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
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
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.CloudUpload
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.Hub
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.WarningAmber
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.zedge.earn.Page
import com.zedge.earn.core.Accounts
import com.zedge.earn.core.ContentTypes
import com.zedge.earn.core.RealTime
import com.zedge.earn.ui.MainViewModel
import com.zedge.earn.ui.components.AnimatedCount
import com.zedge.earn.ui.components.DhakaClock
import com.zedge.earn.ui.components.EmptyState
import com.zedge.earn.ui.components.FailedUploadsSection
import com.zedge.earn.ui.components.MetadataAlertSection
import com.zedge.earn.ui.components.QueueRow
import com.zedge.earn.ui.components.Sparkline
import com.zedge.earn.ui.components.StatusPill
import com.zedge.earn.ui.components.TypeBadge
import com.zedge.earn.ui.components.typeIcon
import com.zedge.earn.ui.theme.BrandBadge
import com.zedge.earn.ui.theme.BrandOnBadge
import com.zedge.earn.ui.theme.Warn
import com.zedge.earn.ui.theme.typeColor
import org.json.JSONObject
import java.util.Calendar
import java.util.TimeZone
import kotlin.math.roundToInt

/**
 * Dashboard v2 — clean, minimalist dark redesign (Fiverr-mobile style):
 * flat solid cards, hairline borders, generous whitespace, one accent colour,
 * big bold numbers for data, small muted labels. No glass, no gradients, no aurora.
 * All data sources, actions and sections from v1 are preserved; only the
 * presentation changed. Other screens are untouched.
 */

// Success / payout accent (used sparingly: live dot, payout pill, progress).
private val DashGreen = Color(0xFF1DBF73)

private fun dhakaGreeting(): String {
    val h = Calendar.getInstance(TimeZone.getTimeZone("Asia/Dhaka")).get(Calendar.HOUR_OF_DAY)
    return when (h) {
        in 5..11 -> "Good morning"
        in 12..16 -> "Good afternoon"
        in 17..21 -> "Good evening"
        else -> "Good night"
    }
}

@Composable
fun HomeScreen(vm: MainViewModel, onOpenPage: (Page) -> Unit) {
    val queueItems by vm.items.collectAsStateWithLifecycle()
    val plan by vm.plan.collectAsStateWithLifecycle()
    val uploadHealth by vm.gateHealth.collectAsStateWithLifecycle()
    val active by vm.activeKey.collectAsStateWithLifecycle()
    val earnings by vm.earnings.collectAsStateWithLifecycle()
    val accountNames by vm.accountNames.collectAsStateWithLifecycle()
    val synced by RealTime.synced.collectAsStateWithLifecycle()
    val queued = queueItems.filter { it.isQueued }
    val failed = queueItems.filter { it.isFailed }
    val noMeta = queued.filter { !it.hasMetadata }   // metadata guard (unchanged)
    fun count(t: String) = queued.count { it.dayType == t }
    val cs = MaterialTheme.colorScheme

    LazyColumn(
        modifier = Modifier.fillMaxSize().background(cs.background),
        contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 12.dp, bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        // ── Greeting header ──────────────────────────────────────────────
        item {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(dhakaGreeting(), style = MaterialTheme.typography.headlineMedium, color = cs.onBackground, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Spacer(Modifier.height(3.dp))
                    Text(
                        "${Accounts.byKey(active).label} · ${RealTime.prettyKey(RealTime.key(RealTime.dhakaDate()))}",
                        style = MaterialTheme.typography.bodyMedium, color = cs.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    )
                }
                Row(
                    Modifier.clip(CircleShape).background(cs.surface).padding(horizontal = 10.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(Modifier.size(7.dp).clip(CircleShape).background(if (synced) DashGreen else cs.error))
                    Spacer(Modifier.width(6.dp))
                    Text(if (synced) "Live" else "Offline", style = MaterialTheme.typography.labelMedium, color = cs.onSurface)
                }
            }
        }

        // ── Today hero card ──────────────────────────────────────────────
        item {
            val today = plan.days.firstOrNull()
            val filled = today?.slots?.count { it != null } ?: 0
            val total = today?.slotCount ?: 0
            DashCard {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("TODAY", style = MaterialTheme.typography.labelSmall, color = cs.onSurfaceVariant, modifier = Modifier.weight(1f))
                    DhakaClock(color = cs.onSurface, style = MaterialTheme.typography.titleMedium)
                }
                Spacer(Modifier.height(10.dp))
                Text(
                    when {
                        today == null -> "Loading schedule…"
                        total == 0 -> "All done for today"
                        else -> "$total ${ContentTypes.dayUi(today.dayType).label} left"
                    },
                    style = MaterialTheme.typography.headlineMedium, color = cs.onSurface, maxLines = 2, overflow = TextOverflow.Ellipsis,
                )
                Spacer(Modifier.height(4.dp))
                Text("${queued.size} in queue · ${Accounts.byKey(active).label}", style = MaterialTheme.typography.bodyMedium, color = cs.onSurfaceVariant)
                if (total > 0) {
                    Spacer(Modifier.height(14.dp))
                    LinearProgressIndicator(
                        progress = { (filled.toFloat() / total).coerceIn(0f, 1f) },
                        modifier = Modifier.fillMaxWidth().height(6.dp).clip(CircleShape),
                        color = DashGreen,
                        trackColor = cs.surfaceVariant,
                    )
                    Spacer(Modifier.height(6.dp))
                    Text("$filled of $total slots filled", style = MaterialTheme.typography.labelMedium, color = cs.onSurfaceVariant)
                }
                Spacer(Modifier.height(16.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Button(onClick = { onOpenPage(Page.UPLOAD) }, contentPadding = PaddingValues(horizontal = 20.dp, vertical = 10.dp)) {
                        Icon(Icons.Default.CloudUpload, null, Modifier.size(17.dp)); Spacer(Modifier.width(7.dp)); Text("Upload")
                    }
                    OutlinedButton(onClick = { onOpenPage(Page.SCHEDULE) }, contentPadding = PaddingValues(horizontal = 20.dp, vertical = 10.dp)) {
                        Icon(Icons.Default.CalendarMonth, null, Modifier.size(17.dp)); Spacer(Modifier.width(7.dp)); Text("Planner")
                    }
                }
            }
        }

        // ── Earnings card ────────────────────────────────────────────────
        item {
            val earnTotal = Accounts.keys.sumOf { k ->
                val d = earnings[k]
                (earnNumH(d, "mtdRevenue") ?: earnNumH(d, "netRevenue") ?: 0.0)
            }
            DashCard {
                DashSectionHeader("Earnings", "Open", { onOpenPage(Page.EARNINGS) })
                Text("All accounts · this month", style = MaterialTheme.typography.bodySmall, color = cs.onSurfaceVariant)
                Spacer(Modifier.height(4.dp))
                Text(earnMoneyH(earnTotal), style = MaterialTheme.typography.displaySmall, color = cs.onSurface)
                if (Accounts.all.isEmpty()) {
                    Spacer(Modifier.height(12.dp))
                    EmptyState("Waiting for the first earnings report from the bot.")
                } else {
                    Accounts.all.forEachIndexed { i, acc ->
                        Spacer(Modifier.height(14.dp))
                        HorizontalDivider(color = cs.outlineVariant)
                        Spacer(Modifier.height(14.dp))
                        EarnAccountRow(
                            label = accountNames[acc.key] ?: ("Zedge " + (i + 1)),
                            tag = "Z" + (i + 1),
                            data = earnings[acc.key],
                        )
                    }
                }
            }
        }

        // Today's upload runs per account (shared strip, unchanged behaviour).
        item { TodayRunStrip(active, plan, uploadHealth) }

        // ── Queue by type ────────────────────────────────────────────────
        item {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                DashSectionHeader("Queue by type")
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    DashStat("Ringtones", count("AUDIO").toString(), Modifier.weight(1f), typeColor("AUDIO"), typeIcon("AUDIO"))
                    DashStat("Wallpapers", count("WALLPAPER").toString(), Modifier.weight(1f), typeColor("WALLPAPER"), typeIcon("WALLPAPER"))
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    DashStat("24H sets", count("WALLPAPER_24H").toString(), Modifier.weight(1f), typeColor("WALLPAPER_24H"), typeIcon("WALLPAPER_24H"))
                    DashStat("Dual sets", count("WALLPAPER_DUAL").toString(), Modifier.weight(1f), typeColor("WALLPAPER_DUAL"), typeIcon("WALLPAPER_DUAL"))
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    DashStat("Battery sets", count("WALLPAPER_BATTERY").toString(), Modifier.weight(1f), typeColor("WALLPAPER_BATTERY"), typeIcon("WALLPAPER_BATTERY"))
                    DashStat("Live wallpapers", count("LIVE_WALLPAPER").toString(), Modifier.weight(1f), typeColor("LIVE_WALLPAPER"), typeIcon("LIVE_WALLPAPER"))
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    DashStat("Charging animations", count("CHARGING_ANIMATION").toString(), Modifier.weight(1f), typeColor("CHARGING_ANIMATION"), typeIcon("CHARGING_ANIMATION"))
                    DashStat("Pinned", queued.count { it.isPinned }.toString(), Modifier.weight(1f), cs.primary, Icons.Default.PushPin)
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    DashStat("Failed uploads", failed.size.toString(), Modifier.weight(1f), cs.error, Icons.Default.ErrorOutline, hint = if (failed.isNotEmpty()) "Needs attention" else null)
                    DashStat("No metadata", noMeta.size.toString(), Modifier.weight(1f), Warn, Icons.Default.WarningAmber, hint = if (noMeta.isNotEmpty()) "Bot skips these" else null)
                }
                DashStat("Total in queue", queueItems.size.toString(), Modifier.fillMaxWidth(), cs.primary, Icons.Default.Inventory2)
            }
        }

        // Metadata guard — always above failed uploads (unchanged section).
        item { MetadataAlertSection(vm, noMeta, active) }

        // Failed uploads (shown only when something went wrong).
        if (failed.isNotEmpty()) {
            item { FailedUploadsSection(vm, failed, Accounts.byKey(active).label, hideWhenEmpty = true) }
        }

        // ── Next 7 days ──────────────────────────────────────────────────
        item {
            DashCard {
                DashSectionHeader("Next 7 days", "Planner", { onOpenPage(Page.SCHEDULE) })
                LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(plan.days.take(7)) { d ->
                        val filledD = d.slots.count { it != null }
                        val full = d.slotCount > 0 && filledD >= d.slotCount
                        Column(
                            Modifier.width(76.dp).clip(RoundedCornerShape(14.dp))
                                .background(if (d.isToday) BrandBadge else cs.surfaceVariant)
                                .clickable { onOpenPage(Page.SCHEDULE) }
                                .padding(horizontal = 8.dp, vertical = 12.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            val fg = if (d.isToday) BrandOnBadge else cs.onSurface
                            Text(if (d.isToday) "TODAY" else d.date.dayOfWeek.name.take(3), style = MaterialTheme.typography.labelSmall, color = if (d.isToday) BrandOnBadge else cs.onSurfaceVariant)
                            Spacer(Modifier.height(2.dp))
                            Text(d.date.dayOfMonth.toString(), style = MaterialTheme.typography.titleLarge, color = fg)
                            Spacer(Modifier.height(6.dp))
                            TypeBadge(d.dayType)
                            Spacer(Modifier.height(6.dp))
                            Text("$filledD/${d.slotCount}", style = MaterialTheme.typography.labelMedium, color = if (full) DashGreen else if (filledD == 0) Warn else fg, textAlign = TextAlign.Center)
                        }
                    }
                }
            }
        }

        // ── Quick actions ────────────────────────────────────────────────
        item {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                DashQuickAction("Pins", Icons.Default.PushPin, Modifier.weight(1f)) { onOpenPage(Page.PINS) }
                DashQuickAction("Distribute", Icons.Default.Hub, Modifier.weight(1f)) { onOpenPage(Page.DISTRIBUTE) }
                DashQuickAction("Planner", Icons.Default.CalendarMonth, Modifier.weight(1f)) { onOpenPage(Page.SCHEDULE) }
            }
        }

        // ── Recent uploads ───────────────────────────────────────────────
        item {
            DashCard {
                DashSectionHeader("Recent uploads", "See all", { onOpenPage(Page.UPLOAD) })
                Text(Accounts.byKey(active).label, style = MaterialTheme.typography.bodySmall, color = cs.onSurfaceVariant)
                Spacer(Modifier.height(8.dp))
                val recent = queueItems.sortedByDescending { it.createdAt }.take(5)
                if (recent.isEmpty()) EmptyState("No uploads yet. Tap Upload to add files.")
                else recent.forEach { item -> QueueRow(item, subtitle = item.status.uppercase(), onClick = { vm.selectedItem.value = item }) }
            }
        }

        // Clearance for the bottom navigation bar.
        item { Spacer(Modifier.height(64.dp)) }
    }
}

/** Flat solid card: surface colour, 1dp hairline border, 20dp radius, no shadow/glass. */
@Composable
private fun DashCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(Modifier.padding(18.dp), content = content)
    }
}

/** Section title row in the Fiverr pattern: bold title left, quiet text action right. */
@Composable
private fun DashSectionHeader(title: String, actionLabel: String? = null, onAction: (() -> Unit)? = null) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurface, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (actionLabel != null && onAction != null) {
            TextButton(onClick = onAction, contentPadding = PaddingValues(horizontal = 6.dp, vertical = 2.dp)) {
                Text(actionLabel, style = MaterialTheme.typography.labelLarge)
                Icon(Icons.Default.ChevronRight, null, Modifier.size(15.dp))
            }
        }
    }
    Spacer(Modifier.height(10.dp))
}

/** One account inside the Earnings card: name + amount, thin progress to the payout threshold, sparkline. */
@Composable
private fun EarnAccountRow(label: String, tag: String, data: JSONObject?) {
    val cs = MaterialTheme.colorScheme
    val payable = earnNumH(data, "mtdRevenue") ?: earnNumH(data, "netRevenue")
    val threshold = earnNumH(data, "threshold") ?: 50.0
    val payout = data?.optBoolean("payoutExpected", false) == true
    val pct = ((payable ?: 0.0) / if (threshold <= 0.0) 1.0 else threshold).coerceIn(0.0, 1.0).toFloat()
    val spark = earnSparkH(data, "sparkRevenue")
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(38.dp).clip(CircleShape).background(cs.primary.copy(alpha = 0.16f)), contentAlignment = Alignment.Center) {
            Text(tag, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.ExtraBold, color = cs.primary)
        }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(label, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold, color = cs.onSurface, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(
                if (data == null) "No report yet" else "Unlocks " + earnCountH(data, "unlocks") + " · " + earnAgoH(data.optLong("updatedAt", 0L)),
                style = MaterialTheme.typography.bodySmall, color = cs.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis,
            )
        }
        Column(horizontalAlignment = Alignment.End) {
            Text(earnMoneyH(payable), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.ExtraBold, color = cs.onSurface)
            if (payout) {
                Spacer(Modifier.height(3.dp))
                StatusPill("payout", DashGreen)
            } else {
                Text("${(pct * 100).roundToInt()}% of ${earnMoneyH(threshold)}", style = MaterialTheme.typography.labelSmall, color = cs.onSurfaceVariant)
            }
        }
    }
    Spacer(Modifier.height(10.dp))
    LinearProgressIndicator(
        progress = { pct },
        modifier = Modifier.fillMaxWidth().height(5.dp).clip(CircleShape),
        color = DashGreen,
        trackColor = cs.surfaceVariant,
    )
    if (spark != null) {
        Spacer(Modifier.height(8.dp))
        Sparkline(spark, cs.primary, Modifier.fillMaxWidth().height(28.dp))
    }
}

/** Minimal stat tile: tinted icon, one big high-contrast number, one muted label. */
@Composable
private fun DashStat(label: String, value: String, modifier: Modifier = Modifier, accent: Color, icon: ImageVector, hint: String? = null) {
    val cs = MaterialTheme.colorScheme
    Card(
        modifier = modifier,
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = cs.surface),
        border = BorderStroke(1.dp, cs.outlineVariant),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(Modifier.padding(14.dp)) {
            Box(Modifier.size(36.dp).clip(RoundedCornerShape(11.dp)).background(accent.copy(alpha = 0.15f)), contentAlignment = Alignment.Center) {
                Icon(icon, null, Modifier.size(19.dp), tint = accent)
            }
            Spacer(Modifier.height(10.dp))
            AnimatedCount(value, MaterialTheme.typography.headlineSmall, cs.onSurface)
            Text(label, style = MaterialTheme.typography.bodySmall, color = cs.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis)
            if (hint != null) {
                Spacer(Modifier.height(2.dp))
                Text(hint, style = MaterialTheme.typography.labelSmall, color = accent, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

@Composable
private fun DashQuickAction(label: String, icon: ImageVector, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    Card(
        modifier = modifier.clickable(onClick = onClick),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = cs.surface),
        border = BorderStroke(1.dp, cs.outlineVariant),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(Modifier.padding(vertical = 14.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Box(Modifier.size(38.dp).clip(CircleShape).background(cs.primary.copy(alpha = 0.15f)), contentAlignment = Alignment.Center) {
                Icon(icon, null, Modifier.size(18.dp), tint = cs.primary)
            }
            Spacer(Modifier.height(7.dp))
            Text(label, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = cs.onSurface, maxLines = 1)
        }
    }
}

// ── Earnings JSON helpers (unchanged from v1) ────────────────────────────

private fun earnMoneyH(v: Double?): String = if (v == null) "--" else "$" + String.format("%,.2f", v)

private fun earnNumH(o: JSONObject?, k: String): Double? {
    if (o == null || !o.has(k) || o.isNull(k)) return null
    val d = o.optDouble(k, Double.NaN)
    return if (d.isNaN()) null else d
}

private fun earnCountH(o: JSONObject?, k: String): String {
    val v = earnNumH(o, k) ?: return "--"
    return String.format("%,d", v.roundToInt())
}

private fun earnAgoH(ms: Long): String {
    if (ms <= 0L) return ""
    val mins = ((System.currentTimeMillis() - ms) / 60000L).toInt()
    return when {
        mins < 1 -> "just now"
        mins < 60 -> "$mins min ago"
        mins < 1440 -> "${mins / 60} h ago"
        else -> "${mins / 1440} d ago"
    }
}

private fun earnSparkH(o: JSONObject?, k: String): List<Float>? {
    val a = o?.optJSONArray(k) ?: return null
    if (a.length() < 2) return null
    val out = ArrayList<Float>(a.length())
    for (i in 0 until a.length()) {
        val v = a.optDouble(i, Double.NaN)
        if (v.isNaN()) return null
        out.add(v.toFloat().coerceIn(0f, 1f))
    }
    return out
}
