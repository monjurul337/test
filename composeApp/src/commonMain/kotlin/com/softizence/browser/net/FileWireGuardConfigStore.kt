package com.softizence.browser.net

import okio.ByteString.Companion.decodeBase64
import okio.ByteString.Companion.encodeUtf8
import okio.FileSystem
import okio.Path.Companion.toPath

/**
 * Stores `.conf` files on disk. The body is sealed with a key held by the platform
 * keystore (passed in as [keyProvider]) so a stolen folder does not hand over the
 * user's WireGuard private keys.
 *
 * The obfuscation here is a keyed XOR stream over base64; both platform hosts wrap this
 * with real OS crypto (EncryptedFile on Android, a DPAPI/Keychain-sealed key on desktop)
 * - this class only guarantees nothing is written in plaintext by accident.
 */
class FileWireGuardConfigStore(
    private val fileSystem: FileSystem,
    private val directory: String,
    private val keyProvider: suspend () -> ByteArray,
) : WireGuardConfigStore {

    override suspend fun loadAll(): Pair<List<WireGuardConfig>, List<String>> {
        val dir = directory.toPath()
        if (!fileSystem.exists(dir)) return emptyList<WireGuardConfig>() to emptyList()
        val key = keyProvider()

        val ok = mutableListOf<WireGuardConfig>()
        val errors = mutableListOf<String>()

        fileSystem.list(dir).filter { it.name.endsWith(SUFFIX) }.forEach { path ->
            val name = path.name.removeSuffix(SUFFIX)
            val text = runCatching {
                unseal(fileSystem.read(path) { readUtf8() }, key)
            }.getOrNull()

            if (text == null) {
                errors += "$name: could not be decrypted (wrong device or corrupt file)."
                return@forEach
            }
            WireGuardConfigParser.parseOrNull("$name.conf", text)
                .onSuccess { ok += it.copy(sourcePath = path.toString()) }
                .onFailure { errors += "$name: ${it.message}" }
        }
        return ok.sortedBy { it.name.lowercase() } to errors
    }

    override suspend fun save(config: WireGuardConfig) {
        fileSystem.createDirectories(directory.toPath())
        val key = keyProvider()
        val path = directory.toPath() / "${config.name.sanitized()}$SUFFIX"
        fileSystem.write(path) { writeUtf8(seal(config.rawText, key)) }
    }

    override suspend fun delete(configId: String) {
        val (configs, _) = loadAll()
        configs.firstOrNull { it.id == configId }?.sourcePath?.let { path ->
            runCatching { fileSystem.delete(path.toPath()) }
        }
    }

    private fun seal(plain: String, key: ByteArray): String {
        val bytes = plain.encodeUtf8().toByteArray()
        return okio.ByteString.of(*xor(bytes, key)).base64()
    }

    private fun unseal(sealed: String, key: ByteArray): String {
        val bytes = sealed.decodeBase64()?.toByteArray() ?: error("not base64")
        return xor(bytes, key).decodeToString()
    }

    private fun xor(data: ByteArray, key: ByteArray): ByteArray {
        require(key.isNotEmpty()) { "Empty encryption key" }
        return ByteArray(data.size) { i -> (data[i].toInt() xor key[i % key.size].toInt()).toByte() }
    }

    private fun String.sanitized() = map { if (it.isLetterOrDigit() || it in "-_.") it else '_' }.joinToString("")

    private companion object { const val SUFFIX = ".conf.sfz" }
}
