package com.visabot.app

import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.launch
import okhttp3.*
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.*

/**
 * ViewModel for MainActivity.
 * Handles business logic for WebSocket connection and state.
 */

data class OtpLogEntry(
    val otp: String,
    val sender: String,
    val rawMessage: String,
    val timeStr: String = SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date()),
)

data class ConnectionStatus(
    val type: Type,
    val message: String,
) {
    enum class Type { CONNECTED, CONNECTING, DISCONNECTED, ERROR }
}

class MainViewModel : ViewModel() {

    private val _connectionStatus = MutableLiveData<ConnectionStatus>(
        ConnectionStatus(ConnectionStatus.Type.DISCONNECTED, "Not connected")
    )
    val connectionStatus: LiveData<ConnectionStatus> = _connectionStatus

    private val _pairingCode = MutableLiveData<String>("")
    val pairingCode: LiveData<String> = _pairingCode

    private val _serviceRunning = MutableLiveData<Boolean>(false)
    val serviceRunning: LiveData<Boolean> = _serviceRunning

    private val _otpLog = MutableLiveData<List<OtpLogEntry>>(emptyList())
    val otpLog: LiveData<List<OtpLogEntry>> = _otpLog

    private val _toastMessage = MutableLiveData<String>("")
    val toastMessage: LiveData<String> = _toastMessage

    fun loadSavedSettings() {
        // This would be populated from SharedPreferences in the real app
    }

    fun pairWithCode(code: String, serverUrl: String) {
        _pairingCode.value = code
        _connectionStatus.value = ConnectionStatus(ConnectionStatus.Type.CONNECTING, "Connecting...")
        // In the real app, this would connect via OtpForwardingService
    }

    fun disconnect() {
        _connectionStatus.value = ConnectionStatus(ConnectionStatus.Type.DISCONNECTED, "Disconnected")
    }

    fun setServiceRunning(running: Boolean) {
        _serviceRunning.value = running
    }

    fun addOtpToLog(otp: String, sender: String, rawMessage: String) {
        val current = _otpLog.value?.toMutableList() ?: mutableListOf()
        current.add(OtpLogEntry(otp, sender, rawMessage))
        _otpLog.value = current
    }

    fun clearOtpLog() {
        _otpLog.value = emptyList()
    }

    fun sendTestOTP(otp: String) {
        addOtpToLog(otp, "TEST", "Test OTP: $otp")
        _toastMessage.value = "Test OTP $otp added to log"
    }

    fun clearToast() {
        _toastMessage.value = ""
    }
}
