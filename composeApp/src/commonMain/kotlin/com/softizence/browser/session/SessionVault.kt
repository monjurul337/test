package com.softizence.browser.session

import com.softizence.browser.core.model.TabState
import kotlinx.serialization.Serializable

/**
 * Persistent session storage: the thing that makes logins survive restarts.
 *
 * Secrets (cookie jars, WireGuard private keys) are encrypted at rest with a
 * platform-backed key - Android Keystore / DPAPI-equivalent on desktop - so an attacker
 * with the files alone gets nothing.
 */
interface SessionVault {
    suspend fun saveWorkspace(snapshot: WorkspaceSnapshot)
    suspend fun loadWorkspace(): WorkspaceSnapshot?

    /** Raw cookie-jar bytes for a profile; engine-specific format, opaque here. */
    suspend fun saveCookieJar(profileId: String, bytes: ByteArray)
    suspend fun loadCookieJar(profileId: String): ByteArray?

    suspend fun putSecret(key: String, value: String)
    suspend fun getSecret(key: String): String?
    suspend fun removeSecret(key: String)

    suspend fun wipeProfile(profileId: String)
}

@Serializable
data class WorkspaceSnapshot(
    val tabs: List<TabState> = emptyList(),
    val activeTabId: String? = null,
    val savedAtEpochMillis: Long = 0,
    val activeTunnelId: String? = null,
)

expect fun createSessionVault(): SessionVault
