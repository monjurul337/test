package com.pcassistant.app

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "pc_assistant/native"
    private var recognizer: SpeechRecognizer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveBridgeConfig" -> {
                        val prefs = getSharedPreferences(WolBridgeService.PREFS, Context.MODE_PRIVATE)
                        prefs.edit()
                            .putString("databaseUrl", call.argument<String>("databaseUrl") ?: "")
                            .putString("pairingCode", call.argument<String>("pairingCode") ?: "")
                            .putString("pcMac", call.argument<String>("pcMac") ?: "")
                            .putString("broadcastIp", call.argument<String>("broadcastIp") ?: "192.168.1.255")
                            .apply()
                        result.success(true)
                    }
                    "startBridgeService" -> {
                        val intent = Intent(this, WolBridgeService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    }
                    "stopBridgeService" -> {
                        stopService(Intent(this, WolBridgeService::class.java))
                        result.success(true)
                    }
                    "sendWakeNow" -> {
                        val mac = call.argument<String>("mac") ?: ""
                        val broadcast = call.argument<String>("broadcast") ?: "192.168.1.255"
                        Thread {
                            val ok = WakeOnLan.send(mac, broadcast)
                            Handler(Looper.getMainLooper()).post { result.success(ok) }
                        }.start()
                    }
                    "startSpeech" -> {
                        val locale = call.argument<String>("locale") ?: "en-US"
                        startSpeech(locale, result)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startSpeech(locale: String, result: MethodChannel.Result) {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 42)
            result.error("NO_PERMISSION", "Microphone permission requested - please tap the mic again.", null)
            return
        }
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            result.error("UNAVAILABLE", "Speech recognition is not available on this device.", null)
            return
        }
        var answered = false
        fun answerOnce(block: () -> Unit) { if (!answered) { answered = true; block() } }
        recognizer?.destroy()
        recognizer = SpeechRecognizer.createSpeechRecognizer(this)
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }
        recognizer?.setRecognitionListener(object : RecognitionListener {
            override fun onResults(results: Bundle?) {
                val text = results
                    ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    ?.firstOrNull() ?: ""
                answerOnce { result.success(text) }
            }
            override fun onError(error: Int) {
                answerOnce { result.error("SPEECH_ERROR", "Recognition error $error", null) }
            }
            override fun onReadyForSpeech(params: Bundle?) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onPartialResults(partialResults: Bundle?) {}
            override fun onEvent(eventType: Int, params: Bundle?) {}
        })
        recognizer?.startListening(intent)
    }

    override fun onDestroy() {
        recognizer?.destroy()
        super.onDestroy()
    }
}
