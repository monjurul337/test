package com.softizence.browser.ui.components

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.softizence.browser.core.model.TunnelState
import com.softizence.browser.core.model.TunnelStatus
import com.softizence.browser.net.NetworkMode
import com.softizence.browser.ui.theme.LocalReduceMotion
import com.softizence.browser.ui.theme.LocalSoftizenceColors

/**
 * The app's trust indicator. It never says "protected" unless traffic is *provably*
 * leaving through the tunnel, and it always shows the observed public IP so the claim
 * is falsifiable by the user.
 */
@Composable
fun TunnelBadge(
    state: TunnelState,
    mode: NetworkMode,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalSoftizenceColors.current
    val reduceMotion = LocalReduceMotion.current

    val (dot, label) = when {
        mode == NetworkMode.Blocked -> colors.tunnelBlocked to "Blocked — tunnel down"
        state.statusEnum == TunnelStatus.Connected -> colors.tunnelUp to (state.activeConfigName ?: "Tunnelled")
        state.statusEnum == TunnelStatus.Connecting -> colors.tunnelPending to "Connecting…"
        state.statusEnum == TunnelStatus.Reconnecting -> colors.tunnelPending to "Reconnecting…"
        state.statusEnum == TunnelStatus.Error -> colors.tunnelBlocked to "Tunnel error"
        else -> colors.muted to "Direct"
    }

    val pulse by rememberInfiniteTransition(label = "pulse").animateFloat(
        initialValue = 0.45f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(900), RepeatMode.Reverse),
        label = "pulseAlpha",
    )
    val dotAlpha = if (reduceMotion || state.statusEnum == TunnelStatus.Connected ||
        state.statusEnum == TunnelStatus.Off
    ) 1f else pulse

    Row(
        modifier = modifier
            .clip(MaterialTheme.shapes.extraLarge)
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .border(1.dp, dot.copy(alpha = 0.35f), MaterialTheme.shapes.extraLarge)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Spacer(
            Modifier
                .size(8.dp)
                .alpha(dotAlpha)
                .clip(CircleShape)
                .background(dot),
        )
        Text(
            text = label,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurface,
        )
        AnimatedContent(targetState = state.publicIp, label = "ip") { ip ->
            if (ip != null) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Spacer(Modifier.width(2.dp))
                    Text(
                        text = "· $ip",
                        style = MaterialTheme.typography.bodySmall,
                        fontFamily = FontFamily.Monospace,
                        color = if (mode == NetworkMode.Tunnelled) colors.tunnelUp else colors.muted,
                    )
                }
            }
        }
        if (state.isUp && (state.rxBytes > 0 || state.txBytes > 0)) {
            Text(
                text = "↓${state.rxBytes.humanBytes()} ↑${state.txBytes.humanBytes()}",
                style = MaterialTheme.typography.labelSmall,
                color = colors.muted,
            )
        }
    }
}

fun Long.humanBytes(): String = when {
    this < 1_024 -> "${this}B"
    this < 1_048_576 -> "${this / 1_024}K"
    this < 1_073_741_824 -> "${this / 1_048_576}M"
    else -> "${this / 1_073_741_824}G"
}
