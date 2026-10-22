package com.softizence.browser

import android.app.Application
import com.softizence.browser.di.AppGraph

class SoftizenceApplication : Application() {
    lateinit var graph: AppGraph
        private set

    override fun onCreate() {
        super.onCreate()
        AppContextHolder.context = applicationContext
        graph = AppGraph.create()
    }
}
