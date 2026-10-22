package com.softizence.browser.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.softizence.browser.ui.theme.LocalSoftizenceColors

@Composable
fun SettingsPanel(vm: BrowserViewModel, modifier: Modifier = Modifier) {
    val config by vm.config.collectAsStateMp()
    val p = config.privacy
    val colors = LocalSoftizenceColors.current

    Column(
        modifier
            .background(MaterialTheme.colorScheme.surface)
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text("Settings", style = MaterialTheme.typography.headlineSmall)
        Text(
            "Stored in config.json — edit it directly for anything not exposed here.",
            style = MaterialTheme.typography.bodySmall,
            color = colors.muted,
            modifier = Modifier.padding(bottom = 12.dp),
        )

        SectionLabel("Anti-detect")
        Toggle("Mask fingerprint", "Coherent persona for UA, WebGL, canvas, audio and screen", p.maskFingerprint) {
            vm.updatePrivacy { s -> s.copy(maskFingerprint = it) }
        }
        Toggle("Block WebRTC", "Prevents the classic real-IP leak behind a VPN", p.blockWebRtc) {
            vm.updatePrivacy { s -> s.copy(blockWebRtc = it) }
        }
        Toggle("Match timezone to exit country", "Keeps the persona consistent with the tunnel", p.spoofTimezoneFromExit) {
            vm.updatePrivacy { s -> s.copy(spoofTimezoneFromExit = it) }
        }

        SectionLabel("Content")
        Toggle("Block third-party cookies", null, p.blockThirdPartyCookies) {
            vm.updatePrivacy { s -> s.copy(blockThirdPartyCookies = it) }
        }
        Toggle("Block known trackers", null, p.blockTrackerHosts) {
            vm.updatePrivacy { s -> s.copy(blockTrackerHosts = it) }
        }
        Toggle("Strip tracking parameters", "utm_*, gclid, fbclid and friends", p.stripTrackingParams) {
            vm.updatePrivacy { s -> s.copy(stripTrackingParams = it) }
        }
        Toggle("Force HTTPS", null, p.forceHttps) {
            vm.updatePrivacy { s -> s.copy(forceHttps = it) }
        }

        SectionLabel("Appearance")
        Toggle("Light theme", null, config.appearance.theme == "porcelain") {
            vm.updateAppearance { a -> a.copy(theme = if (it) "porcelain" else "obsidian") }
        }
        Toggle("Reduce motion", null, config.appearance.reduceMotion) {
            vm.updateAppearance { a -> a.copy(reduceMotion = it) }
        }
    }
}

@Composable
private fun SectionLabel(text: String) {
    Text(
        text.uppercase(),
        style = MaterialTheme.typography.labelSmall,
        color = LocalSoftizenceColors.current.muted,
        modifier = Modifier.padding(top = 16.dp, bottom = 6.dp),
    )
}

@Composable
private fun Toggle(title: String, subtitle: String?, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            subtitle?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = LocalSoftizenceColors.current.muted)
            }
        }
        Switch(checked = checked, onCheckedChange = onChange)
    }
}
