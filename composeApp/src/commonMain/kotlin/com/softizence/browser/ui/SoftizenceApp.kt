package com.softizence.browser.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowBack
import androidx.compose.material.icons.rounded.ArrowForward
import androidx.compose.material.icons.rounded.Extension
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.VpnKey
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Snackbar
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import com.softizence.browser.browser.WebSurface
import com.softizence.browser.net.NetworkMode
import com.softizence.browser.ui.components.Omnibox
import com.softizence.browser.ui.components.TabRail
import com.softizence.browser.ui.components.TunnelBadge
import com.softizence.browser.ui.components.resolveInput
import com.softizence.browser.ui.screens.ExtensionsPanel
import com.softizence.browser.ui.screens.HomeScreen
import com.softizence.browser.ui.screens.Shortcut
import com.softizence.browser.ui.screens.TunnelPanel
import com.softizence.browser.ui.theme.LocalSoftizenceColors
import com.softizence.browser.ui.theme.SoftizenceTheme
import kotlinx.coroutines.flow.collectLatest

/**
 * The shared shell. Layout adapts to the window, not to the OS name:
 * a wide window gets the vertical brass rail + side panels (desktop feel),
 * a narrow one collapses to a bottom-anchored omnibox (phone feel).
 */
@Composable
fun SoftizenceApp(vm: BrowserViewModel) {
    val config by vm.config.collectAsStateMp()
    SoftizenceTheme(
        dark = config.appearance.theme != "porcelain",
        cornerRadius = config.appearance.cornerRadiusDp,
        fontScale = config.appearance.fontScale,
        reduceMotion = config.appearance.reduceMotion,
    ) {
        BoxWithConstraints(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
            val wide = maxWidth > 840.dp
            if (wide) WideLayout(vm) else CompactLayout(vm)
        }
    }
}

@Composable
private fun WideLayout(vm: BrowserViewModel) {
    val tabs by vm.tabs.collectAsStateMp()
    val activeId by vm.activeTabId.collectAsStateMp()
    val panel by vm.panel.collectAsStateMp()

    Row(Modifier.fillMaxSize()) {
        TabRail(
            tabs = tabs,
            activeTabId = activeId,
            onSelect = vm::selectTab,
            onClose = vm::closeTab,
            onNewTab = { vm.newTab() },
        )
        VerticalHairline()
        Column(Modifier.weight(1f).fillMaxHeight()) {
            ChromeBar(vm)
            Box(Modifier.weight(1f)) { Viewport(vm) }
        }
        AnimatedVisibility(
            visible = panel != SidePanel.None,
            enter = slideInHorizontally { it },
            exit = slideOutHorizontally { it },
        ) {
            Row(Modifier.fillMaxHeight()) {
                VerticalHairline()
                SidePanelHost(vm, Modifier.width(380.dp).fillMaxHeight())
            }
        }
    }
}

@Composable
private fun CompactLayout(vm: BrowserViewModel) {
    val panel by vm.panel.collectAsStateMp()
    Column(Modifier.fillMaxSize()) {
        Box(Modifier.weight(1f)) {
            if (panel == SidePanel.None) Viewport(vm) else SidePanelHost(vm, Modifier.fillMaxSize())
        }
        HorizontalHairline()
        ChromeBar(vm, compact = true)
    }
}

@Composable
private fun ChromeBar(vm: BrowserViewModel, compact: Boolean = false) {
    val colors = LocalSoftizenceColors.current
    val tabs by vm.tabs.collectAsStateMp()
    val activeId by vm.activeTabId.collectAsStateMp()
    val tunnel by vm.tunnelState.collectAsStateMp()
    val mode by vm.networkMode.collectAsStateMp()
    val notice by vm.notice.collectAsStateMp()
    val active = tabs.firstOrNull { it.id == activeId }

    var field by remember(activeId) { mutableStateOf(TextFieldValue(active?.url.orEmpty())) }
    LaunchedEffect(active?.url) {
        active?.url?.let { if (it != field.text) field = TextFieldValue(it) }
    }
    val focusRequester = remember { FocusRequester() }

    Column {
        Row(
            Modifier
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.surface)
                .padding(horizontal = 10.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            NavButton(Icons.Rounded.ArrowBack, "Back", active?.canGoBack == true, vm::back)
            if (!compact) NavButton(Icons.Rounded.ArrowForward, "Forward", active?.canGoForward == true, vm::forward)
            NavButton(Icons.Rounded.Refresh, "Reload", true, vm::reload)
            Spacer(Modifier.width(4.dp))
            Omnibox(
                value = field,
                onValueChange = { field = it },
                onSubmit = { vm.navigate(resolveInput(it, vm::searchUrl)) },
                focusRequester = focusRequester,
                modifier = Modifier.weight(1f),
            )
            Spacer(Modifier.width(4.dp))
            TunnelBadge(tunnel, mode, onClick = { vm.openPanel(SidePanel.Tunnels) })
            NavButton(Icons.Rounded.Extension, "Extensions", true) { vm.openPanel(SidePanel.Extensions) }
            NavButton(Icons.Rounded.VpnKey, "Tunnels", true) { vm.openPanel(SidePanel.Tunnels) }
            NavButton(Icons.Rounded.Settings, "Settings", true) { vm.openPanel(SidePanel.Settings) }
        }
        // Page-load progress rendered as a hairline of brass across the chrome.
        val progress = active?.progress ?: 0f
        if (active?.isLoading == true) {
            Box(
                Modifier
                    .fillMaxWidth(progress.coerceIn(0.02f, 1f))
                    .height(2.dp)
                    .background(colors.accent),
            )
        }
        notice?.let { message ->
            LaunchedEffect(message) { }
            Snackbar(
                modifier = Modifier.padding(8.dp),
                action = { Text("Dismiss", modifier = Modifier.padding(8.dp)) },
            ) { Text(message) }
        }
    }
}

@Composable
private fun Viewport(vm: BrowserViewModel) {
    val tabs by vm.tabs.collectAsStateMp()
    val activeId by vm.activeTabId.collectAsStateMp()
    val mode by vm.networkMode.collectAsStateMp()
    val tunnel by vm.tunnelState.collectAsStateMp()
    val active = tabs.firstOrNull { it.id == activeId }

    when {
        active == null -> Box(Modifier.fillMaxSize())
        active.url == "softizence://home" -> HomeScreen(
            mode = mode,
            publicIp = tunnel.publicIp,
            shortcuts = defaultShortcuts,
            onOpen = { vm.navigate(it) },
            modifier = Modifier.fillMaxSize(),
        )
        else -> WebSurface(vm.engine, active.id, Modifier.fillMaxSize())
    }
}

@Composable
private fun SidePanelHost(vm: BrowserViewModel, modifier: Modifier) {
    val panel by vm.panel.collectAsStateMp()
    val configs by vm.tunnels.configs.collectAsStateMp()
    val tunnel by vm.tunnelState.collectAsStateMp()
    val mode by vm.networkMode.collectAsStateMp()
    val policy by vm.tunnels.policy.collectAsStateMp()
    val exts by vm.extensions.extensions.collectAsStateMp()

    when (panel) {
        SidePanel.Tunnels -> TunnelPanel(
            configs = configs,
            state = tunnel,
            mode = mode,
            killSwitch = policy.killSwitch,
            onImport = { vm.onPickConfigs?.invoke() },
            onActivate = vm::activateTunnel,
            onDeactivate = { vm.deactivateTunnel() },
            onRemove = vm::removeTunnel,
            onKillSwitchChange = vm::setKillSwitch,
            modifier = modifier,
        )
        SidePanel.Extensions -> ExtensionsPanel(
            extensions = exts,
            capabilities = vm.extensions.capabilities,
            onLoadFolder = { vm.onPickExtensionFolder?.invoke() },
            onToggle = vm::toggleExtension,
            modifier = modifier,
        )
        SidePanel.Settings -> SettingsPanel(vm, modifier)
        SidePanel.None -> Box(modifier)
    }
}

@Composable
private fun NavButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    val colors = LocalSoftizenceColors.current
    IconButton(onClick = onClick, enabled = enabled, modifier = Modifier.size(34.dp)) {
        Icon(
            icon,
            label,
            tint = if (enabled) MaterialTheme.colorScheme.onSurface else colors.muted.copy(alpha = 0.4f),
            modifier = Modifier.size(17.dp),
        )
    }
}

@Composable
private fun VerticalHairline() {
    Box(
        Modifier
            .width(1.dp)
            .fillMaxHeight()
            .background(LocalSoftizenceColors.current.hairline),
    )
}

@Composable
private fun HorizontalHairline() {
    Box(
        Modifier
            .fillMaxWidth()
            .height(1.dp)
            .background(LocalSoftizenceColors.current.hairline),
    )
}

private val defaultShortcuts = listOf(
    Shortcut("Proton", "https://account.proton.me"),
    Shortcut("Notion", "https://www.notion.so"),
    Shortcut("GitHub", "https://github.com"),
    Shortcut("DuckDuckGo", "https://duckduckgo.com"),
)

/** Tiny shim so the shell stays free of platform lifecycle imports. */
@Composable
internal fun <T> kotlinx.coroutines.flow.StateFlow<T>.collectAsStateMp(): androidx.compose.runtime.State<T> {
    val state = androidx.compose.runtime.remember(this) { androidx.compose.runtime.mutableStateOf(value) }
    LaunchedEffect(this) { collectLatest { state.value = it } }
    return state
}
