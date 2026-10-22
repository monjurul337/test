package com.softizence.browser.ui.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.Public
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import com.softizence.browser.ui.theme.LocalSoftizenceColors

/**
 * One field for URLs, searches and commands. The leading glyph is a *security* signal,
 * not decoration: brass lock = HTTPS, muted globe = plain HTTP (which the privacy engine
 * will upgrade), magnifier = this will be a search.
 */
@Composable
fun Omnibox(
    value: TextFieldValue,
    onValueChange: (TextFieldValue) -> Unit,
    onSubmit: (String) -> Unit,
    focusRequester: FocusRequester,
    modifier: Modifier = Modifier,
    placeholder: String = "Search or enter address",
) {
    val colors = LocalSoftizenceColors.current
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()
    val borderColor by animateColorAsState(
        if (focused) colors.accent.copy(alpha = 0.7f) else colors.hairline,
        label = "omniboxBorder",
    )

    val text = value.text
    val isSearch = !text.contains("://") && (' ' in text || '.' !in text)
    val secure = text.startsWith("https://")

    Row(
        modifier = modifier
            .heightIn(min = 40.dp)
            .clip(MaterialTheme.shapes.extraLarge)
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .border(1.dp, borderColor, MaterialTheme.shapes.extraLarge)
            .padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(
            imageVector = when {
                isSearch -> Icons.Rounded.Search
                secure -> Icons.Rounded.Lock
                else -> Icons.Rounded.Public
            },
            contentDescription = null,
            tint = if (secure) colors.accent else colors.muted,
            modifier = Modifier.size(16.dp),
        )
        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
            if (text.isEmpty()) {
                Text(placeholder, style = MaterialTheme.typography.bodyMedium, color = colors.muted)
            }
            BasicTextField(
                value = value,
                onValueChange = onValueChange,
                singleLine = true,
                interactionSource = interaction,
                textStyle = LocalTextStyle.current.merge(
                    MaterialTheme.typography.bodyMedium.copy(color = MaterialTheme.colorScheme.onSurface),
                ),
                cursorBrush = androidx.compose.ui.graphics.SolidColor(colors.accent),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Go),
                keyboardActions = KeyboardActions(onGo = { onSubmit(text) }),
                modifier = Modifier.fillMaxWidth().focusRequester(focusRequester),
            )
        }
    }
}

/**
 * Turns whatever the user typed into a navigable URL.
 * Kept pure so it is trivially unit-testable.
 */
fun resolveInput(raw: String, searchUrl: (String) -> String): String {
    val input = raw.trim()
    return when {
        input.isEmpty() -> "softizence://home"
        input.startsWith("softizence://") -> input
        input.contains("://") -> input
        input.startsWith("localhost") || input.matches(IPV4) -> "http://$input"
        // "notion.so/page", "example.com" -> a host; "how to cook rice" -> a search
        !input.contains(' ') && input.substringBefore('/').contains('.') -> "https://$input"
        else -> searchUrl(input)
    }
}

private val IPV4 = Regex("""^\d{1,3}(\.\d{1,3}){3}(:\d+)?(/.*)?$""")
