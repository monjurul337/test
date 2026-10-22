package com.softizence.browser.session

import com.softizence.browser.AppContextHolder

actual fun createSessionVault(): SessionVault = AndroidSessionVault(AppContextHolder.context)
