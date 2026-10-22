package com.softizence.browser.session

import com.softizence.browser.ExtensionPaths

actual fun createSessionVault(): SessionVault = DesktopSessionVault(ExtensionPaths.profilesDir)
