package com.softizence.browser.di

import com.softizence.browser.ExtensionPaths
import com.softizence.browser.extensions.DesktopExtensionHost
import com.softizence.browser.extensions.ExtensionHost
import com.softizence.browser.net.DesktopTunnelController
import com.softizence.browser.net.PublicIpResolver
import com.softizence.browser.net.TunnelController
import io.ktor.client.HttpClient
import io.ktor.client.engine.java.Java
import okio.FileSystem

actual fun platformFileSystem(): FileSystem = FileSystem.SYSTEM

actual fun createHttpClient(): HttpClient = HttpClient(Java) {
    engine {
        // Follow the OS routing table (which the tunnel owns) - never a cached proxy.
        protocolVersion = java.net.http.HttpClient.Version.HTTP_1_1
    }
}

actual fun createTunnelController(ipResolver: PublicIpResolver): TunnelController =
    DesktopTunnelController(ipResolver)

actual fun createExtensionHost(): ExtensionHost = DesktopExtensionHost(ExtensionPaths.extensionsDir)
