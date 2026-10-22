package com.softizence.browser.session

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import java.io.File
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import java.util.Base64

/**
 * Desktop vault: AES-256-GCM with a key stored in a 0600 keyfile under the app data
 * directory. On Windows/macOS the enclosing directory is already user-scoped; the keyfile
 * permissions are tightened further so another local account cannot read it.
 */
class DesktopSessionVault(private val directory: String) : SessionVault {

    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private val random = SecureRandom()

    private val key: SecretKey by lazy {
        val keyFile = File(directory, ".vaultkey")
        if (keyFile.exists()) {
            SecretKeySpec(Base64.getDecoder().decode(keyFile.readText().trim()), "AES")
        } else {
            val generated = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()
            keyFile.parentFile.mkdirs()
            keyFile.writeText(Base64.getEncoder().encodeToString(generated.encoded))
            keyFile.setReadable(false, false)
            keyFile.setReadable(true, true)
            generated
        }
    }

    override suspend fun saveWorkspace(snapshot: WorkspaceSnapshot) = withContext(Dispatchers.IO) {
        write("workspace.json", json.encodeToString(WorkspaceSnapshot.serializer(), snapshot).toByteArray())
    }

    override suspend fun loadWorkspace(): WorkspaceSnapshot? = withContext(Dispatchers.IO) {
        read("workspace.json")?.let {
            runCatching { json.decodeFromString(WorkspaceSnapshot.serializer(), it.decodeToString()) }.getOrNull()
        }
    }

    override suspend fun saveCookieJar(profileId: String, bytes: ByteArray) = withContext(Dispatchers.IO) {
        write("cookies_$profileId.bin", bytes)
    }

    override suspend fun loadCookieJar(profileId: String): ByteArray? = withContext(Dispatchers.IO) {
        read("cookies_$profileId.bin")
    }

    override suspend fun putSecret(key: String, value: String) = withContext(Dispatchers.IO) {
        write("secret_${key.hashCode()}.bin", value.toByteArray())
    }

    override suspend fun getSecret(key: String): String? = withContext(Dispatchers.IO) {
        read("secret_${key.hashCode()}.bin")?.decodeToString()
    }

    override suspend fun removeSecret(key: String) = withContext(Dispatchers.IO) {
        File(directory, "secret_${key.hashCode()}.bin").delete()
        Unit
    }

    override suspend fun wipeProfile(profileId: String) = withContext(Dispatchers.IO) {
        File(directory, profileId).deleteRecursively()
        File(directory, "cookies_$profileId.bin").delete()
        Unit
    }

    private fun write(name: String, plain: ByteArray) {
        val iv = ByteArray(IV_BYTES).also(random::nextBytes)
        val cipher = Cipher.getInstance(TRANSFORM).apply {
            init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(TAG_BITS, iv))
        }
        val sealed = cipher.doFinal(plain)
        File(directory).mkdirs()
        File(directory, name).writeBytes(iv + sealed)
    }

    private fun read(name: String): ByteArray? {
        val file = File(directory, name)
        if (!file.exists()) return null
        return runCatching {
            val bytes = file.readBytes()
            val cipher = Cipher.getInstance(TRANSFORM).apply {
                init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_BITS, bytes, 0, IV_BYTES))
            }
            cipher.doFinal(bytes, IV_BYTES, bytes.size - IV_BYTES)
        }.getOrNull()
    }

    private companion object {
        const val TRANSFORM = "AES/GCM/NoPadding"
        const val IV_BYTES = 12
        const val TAG_BITS = 128
    }
}
