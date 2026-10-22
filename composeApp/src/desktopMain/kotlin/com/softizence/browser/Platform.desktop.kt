package com.softizence.browser

import com.softizence.browser.browser.BrowserEngine
import com.softizence.browser.browser.CefBrowserEngine
import java.io.File

/**
 * Desktop paths follow each OS's convention rather than dumping a dotfolder in $HOME.
 *   Windows  %LOCALAPPDATA%\Softizence
 *   macOS    ~/Library/Application Support/Softizence
 *   Linux    $XDG_DATA_HOME/softizence (or ~/.local/share/softizence)
 */
actual object ExtensionPaths {
    private val base: String by lazy {
        val os = System.getProperty("os.name").lowercase()
        val home = System.getProperty("user.home")
        val dir = when {
            "win" in os -> File(System.getenv("LOCALAPPDATA") ?: "$home\\AppData\\Local", "Softizence")
            "mac" in os -> File(home, "Library/Application Support/Softizence")
            else -> File(System.getenv("XDG_DATA_HOME") ?: "$home/.local/share", "softizence")
        }
        dir.mkdirs()
        dir.absolutePath
    }

    actual val extensionsDir: String get() = ensure("extensions")
    actual val tunnelsDir: String get() = ensure("tunnels")
    actual val profilesDir: String get() = ensure("profiles")
    actual val configDir: String get() = ensure("config")

    /** CEF's own cache/binaries live here too, so the install stays self-contained. */
    val cefDir: String get() = ensure("cef")

    private fun ensure(name: String) = File(base, name).apply { mkdirs() }.absolutePath
}

actual fun platformName(): String =
    "${System.getProperty("os.name")} ${System.getProperty("os.arch")}"

actual fun createBrowserEngine(): BrowserEngine = CefBrowserEngine()
