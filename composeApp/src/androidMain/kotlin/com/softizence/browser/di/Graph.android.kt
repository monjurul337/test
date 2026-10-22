package com.softizence.browser.di

import com.softizence.browser.AppContextHolder
import com.softizence.browser.ExtensionPaths
import com.softizence.browser.extensions.AndroidExtensionHost
import com.softizence.browser.extensions.ExtensionHost
import com.softizence.browser.net.AndroidTunnelController
import com.softizence.browser.net.PublicIpResolver
import com.softizence.browser.net.TunnelController
import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import okio.FileSystem

actual fun platformFileSystem(): FileSystem = FileSystem.SYSTEM

actual fun createHttpClient(): HttpClient = HttpClient(OkHttp) {
    engine {
        config {
            retryOnConnectionFailure(true)
            // Never reuse a pooled connection established before the tunnel came up.
            connectionPool(okhttp3.ConnectionPool(0, 1, java.util.concurrent.TimeUnit.MINUTES))
        }
    }
}

actual fun createTunnelController(ipResolver: PublicIpResolver): TunnelController =
    AndroidTunnelController(AppContextHolder.context, ipResolver)

actual fun createExtensionHost(): ExtensionHost = AndroidExtensionHost(ExtensionPaths.extensionsDir)
