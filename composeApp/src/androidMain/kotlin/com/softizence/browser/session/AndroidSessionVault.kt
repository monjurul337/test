package com.softizence.browser.session

import android.content.Context
import androidx.security.crypto.EncryptedFile
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import java.io.File

/**
 * Android persistence backed by the hardware Keystore (StrongBox when present).
 * Cookie jars and tunnel keys are written through [EncryptedFile]; small secrets go to
 * [EncryptedSharedPreferences].
 */
class AndroidSessionVault(private val context: Context) : SessionVault {

    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    private val masterKey: MasterKey by lazy {
        MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .setRequestStrongBoxBacked(true)
            .build()
    }

    private val prefs by lazy {
        EncryptedSharedPreferences.create(
            context,
            "softizence_secrets",
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    private fun encryptedFile(name: String) = EncryptedFile.Builder(
        context,
        File(context.filesDir, name),
        masterKey,
        EncryptedFile.FileEncryptionScheme.AES256_GCM_HKDF_4KB,
    ).build()

    override suspend fun saveWorkspace(snapshot: WorkspaceSnapshot) = withContext(Dispatchers.IO) {
        writeEncrypted("workspace.json", json.encodeToString(WorkspaceSnapshot.serializer(), snapshot).toByteArray())
    }

    override suspend fun loadWorkspace(): WorkspaceSnapshot? = withContext(Dispatchers.IO) {
        readEncrypted("workspace.json")?.let {
            runCatching { json.decodeFromString(WorkspaceSnapshot.serializer(), it.decodeToString()) }.getOrNull()
        }
    }

    override suspend fun saveCookieJar(profileId: String, bytes: ByteArray) = withContext(Dispatchers.IO) {
        writeEncrypted("cookies_$profileId.bin", bytes)
    }

    override suspend fun loadCookieJar(profileId: String): ByteArray? = withContext(Dispatchers.IO) {
        readEncrypted("cookies_$profileId.bin")
    }

    override suspend fun putSecret(key: String, value: String) = withContext(Dispatchers.IO) {
        prefs.edit().putString(key, value).apply()
    }

    override suspend fun getSecret(key: String): String? = withContext(Dispatchers.IO) {
        prefs.getString(key, null)
    }

    override suspend fun removeSecret(key: String) = withContext(Dispatchers.IO) {
        prefs.edit().remove(key).apply()
    }

    override suspend fun wipeProfile(profileId: String) = withContext(Dispatchers.IO) {
        File(context.filesDir, "cookies_$profileId.bin").delete()
        File(context.filesDir, "profiles/$profileId").deleteRecursively()
        Unit
    }

    private fun writeEncrypted(name: String, bytes: ByteArray) {
        File(context.filesDir, name).delete()   // EncryptedFile refuses to overwrite
        encryptedFile(name).openFileOutput().use { it.write(bytes) }
    }

    private fun readEncrypted(name: String): ByteArray? {
        if (!File(context.filesDir, name).exists()) return null
        return runCatching { encryptedFile(name).openFileInput().use { it.readBytes() } }.getOrNull()
    }
}
