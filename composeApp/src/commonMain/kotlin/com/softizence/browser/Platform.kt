package com.softizence.browser

import com.softizence.browser.browser.BrowserEngine

/** Platform file-system anchors, resolved once at start-up. */
expect object ExtensionPaths {
    /** Unpacked MV3 extensions, one folder per extension. */
    val extensionsDir: String
    /** Imported Proton `.conf` files (encrypted at rest). */
    val tunnelsDir: String
    /** Cookie jars / local storage, partitioned per browsing profile. */
    val profilesDir: String
    /** `config.json` + overrides. */
    val configDir: String
}

expect fun platformName(): String

/** Factory for the platform engine. */
expect fun createBrowserEngine(): BrowserEngine
