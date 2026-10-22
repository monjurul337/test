package com.softizence.browser.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * "Obsidian & Brass" - the Softizence identity.
 *
 * The brief is *luxurious, not generic*: near-black lacquer surfaces with a warm brass
 * accent used sparingly (only for state that matters - the tunnel, the active tab, focus).
 * Chrome recedes; the page is the jewel in the setting.
 */
object Obsidian {
    val Ink = Color(0xFF0B0C10)          // app background - deep, slightly blue-black
    val Lacquer = Color(0xFF121419)      // raised surface
    val Slate = Color(0xFF191C23)        // controls
    val Graphite = Color(0xFF242832)     // borders / dividers
    val Smoke = Color(0xFF8A90A0)        // secondary text
    val Porcelain = Color(0xFFEDEFF4)    // primary text

    val Brass = Color(0xFFC9A227)        // signature accent
    val BrassLight = Color(0xFFE8C65A)
    val BrassDim = Color(0x33C9A227)

    val Jade = Color(0xFF3FBF8F)         // tunnel up
    val Amber = Color(0xFFE2A33C)        // connecting
    val Garnet = Color(0xFFD9534F)       // blocked / error
    val Lapis = Color(0xFF4C6FFF)        // links / info
}

@Immutable
data class SoftizenceColors(
    val tunnelUp: Color = Obsidian.Jade,
    val tunnelPending: Color = Obsidian.Amber,
    val tunnelBlocked: Color = Obsidian.Garnet,
    val accent: Color = Obsidian.Brass,
    val accentSoft: Color = Obsidian.BrassDim,
    val hairline: Color = Obsidian.Graphite,
    val muted: Color = Obsidian.Smoke,
    /** Subtle vertical sheen that gives surfaces their lacquered feel. */
    val chromeSheen: Brush = Brush.verticalGradient(
        listOf(Color(0x14FFFFFF), Color(0x00FFFFFF), Color(0x10000000)),
    ),
    val railGlow: Brush = Brush.verticalGradient(
        listOf(Color(0x00C9A227), Color(0x55C9A227), Color(0x00C9A227)),
    ),
)

val LocalSoftizenceColors = staticCompositionLocalOf { SoftizenceColors() }
val LocalReduceMotion = staticCompositionLocalOf { false }

private val DarkScheme = darkColorScheme(
    primary = Obsidian.Brass,
    onPrimary = Color(0xFF1A1500),
    primaryContainer = Color(0xFF3A2F08),
    onPrimaryContainer = Obsidian.BrassLight,
    secondary = Obsidian.Lapis,
    background = Obsidian.Ink,
    onBackground = Obsidian.Porcelain,
    surface = Obsidian.Lacquer,
    onSurface = Obsidian.Porcelain,
    surfaceVariant = Obsidian.Slate,
    onSurfaceVariant = Obsidian.Smoke,
    outline = Obsidian.Graphite,
    error = Obsidian.Garnet,
)

private val LightScheme = lightColorScheme(
    primary = Color(0xFF8A6D10),
    onPrimary = Color.White,
    background = Color(0xFFF7F5F0),
    onBackground = Color(0xFF14161A),
    surface = Color(0xFFFFFDF8),
    onSurface = Color(0xFF14161A),
    surfaceVariant = Color(0xFFECE8DE),
    onSurfaceVariant = Color(0xFF585B63),
    outline = Color(0xFFD9D3C5),
    error = Obsidian.Garnet,
)

private fun shapes(radius: Int) = Shapes(
    extraSmall = RoundedCornerShape((radius / 3).dp),
    small = RoundedCornerShape((radius / 2).dp),
    medium = RoundedCornerShape(radius.dp),
    large = RoundedCornerShape((radius * 1.4).dp),
    extraLarge = RoundedCornerShape((radius * 2).dp),
)

private fun typography(scale: Float) = Typography().run {
    copy(
        displaySmall = displaySmall.copy(fontSize = 34.sp * scale, fontWeight = FontWeight.Light, letterSpacing = (-0.5).sp),
        headlineSmall = headlineSmall.copy(fontSize = 21.sp * scale, fontWeight = FontWeight.Medium),
        titleMedium = titleMedium.copy(fontSize = 15.sp * scale, fontWeight = FontWeight.Medium, letterSpacing = 0.1.sp),
        bodyMedium = bodyMedium.copy(fontSize = 14.sp * scale),
        bodySmall = bodySmall.copy(fontSize = 12.sp * scale, letterSpacing = 0.2.sp),
        labelSmall = labelSmall.copy(fontSize = 10.sp * scale, fontWeight = FontWeight.SemiBold, letterSpacing = 0.8.sp),
    )
}

@Composable
fun SoftizenceTheme(
    dark: Boolean = isSystemInDarkTheme(),
    cornerRadius: Int = 18,
    fontScale: Float = 1f,
    reduceMotion: Boolean = false,
    content: @Composable () -> Unit,
) {
    CompositionLocalProvider(
        LocalSoftizenceColors provides SoftizenceColors(),
        LocalReduceMotion provides reduceMotion,
    ) {
        MaterialTheme(
            colorScheme = if (dark) DarkScheme else LightScheme,
            shapes = shapes(cornerRadius),
            typography = typography(fontScale),
            content = content,
        )
    }
}
