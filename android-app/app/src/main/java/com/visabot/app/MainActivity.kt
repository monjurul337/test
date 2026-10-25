package com.visabot.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.lifecycle.ViewModelProvider
import com.google.android.material.snackbar.Snackbar
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions
import com.visabot.app.databinding.ActivityMainBinding

/**
 * MainActivity - Main UI for IVAC Visa Bot Android App
 * Features:
 * - Pairing code entry (manual or QR scan)
 * - Connection status display
 * - OTP log feed
 * - Service control (start/stop)
 */
class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private lateinit var viewModel: MainViewModel

    // ─── Permission launchers ──────────────────────────────────────────────────
    private val smsPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { perms ->
        val allGranted = perms.values.all { it }
        if (allGranted) startOtpService()
        else showSnackbar("SMS permission required to forward OTPs")
    }

    private val notifPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { /* Continue regardless */ }

    private val qrScanLauncher = registerForActivityResult(ScanContract()) { result ->
        if (result.contents != null) {
            // QR code contains: "visabot://pair/<pairingCode>@<serverUrl>" or just the 6-digit code
            val content = result.contents
            val codeMatch = Regex("\\d{6}").find(content)
            if (codeMatch != null) {
                binding.etPairingCode.setText(codeMatch.value)
                // Extract server URL if present
                val urlMatch = Regex("https?://[\\w.:/]+").find(content)
                if (urlMatch != null) {
                    binding.etServerUrl.setText(urlMatch.value)
                }
                viewModel.pairWithCode(codeMatch.value, binding.etServerUrl.text.toString())
            } else {
                showSnackbar("Invalid QR code format")
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        viewModel = ViewModelProvider(this)[MainViewModel::class.java]

        setupUI()
        observeViewModel()
        requestPermissionsIfNeeded()

        // Restore saved settings
        viewModel.loadSavedSettings()
    }

    private fun setupUI() {
        // Connect/Disconnect button
        binding.btnConnect.setOnClickListener {
            val code = binding.etPairingCode.text.toString().trim()
            val serverUrl = binding.etServerUrl.text.toString().trim()
            if (code.length != 6 || !code.all { it.isDigit() }) {
                showSnackbar("Enter a valid 6-digit pairing code")
                return@setOnClickListener
            }
            if (serverUrl.isEmpty()) {
                showSnackbar("Enter the server URL")
                return@setOnClickListener
            }
            viewModel.pairWithCode(code, serverUrl)
        }

        binding.btnDisconnect.setOnClickListener {
            viewModel.disconnect()
        }

        // QR scan button
        binding.btnScanQr.setOnClickListener {
            val options = ScanOptions()
                .setPrompt("Scan the pairing QR code from the Chrome Extension")
                .setBeepEnabled(true)
                .setBarcodeImageEnabled(false)
            qrScanLauncher.launch(options)
        }

        // Start/Stop service button
        binding.btnToggleService.setOnClickListener {
            if (viewModel.serviceRunning.value == true) {
                stopOtpService()
            } else {
                checkSmsPermissionsAndStart()
            }
        }

        // Clear OTP log
        binding.btnClearLog.setOnClickListener {
            viewModel.clearOtpLog()
        }

        // Test OTP button (for debugging)
        binding.btnTestOtp.setOnClickListener {
            viewModel.sendTestOTP("123456")
        }
    }

    private fun observeViewModel() {
        viewModel.connectionStatus.observe(this) { status ->
            binding.tvConnectionStatus.text = status.message
            binding.tvConnectionStatus.setTextColor(
                getColor(when (status.type) {
                    ConnectionStatus.Type.CONNECTED    -> R.color.status_connected
                    ConnectionStatus.Type.CONNECTING   -> R.color.status_connecting
                    ConnectionStatus.Type.DISCONNECTED -> R.color.status_disconnected
                    ConnectionStatus.Type.ERROR        -> R.color.status_error
                })
            )
            binding.statusIndicator.setBackgroundResource(
                when (status.type) {
                    ConnectionStatus.Type.CONNECTED    -> R.drawable.indicator_green
                    ConnectionStatus.Type.CONNECTING   -> R.drawable.indicator_yellow
                    ConnectionStatus.Type.DISCONNECTED -> R.drawable.indicator_grey
                    ConnectionStatus.Type.ERROR        -> R.drawable.indicator_red
                }
            )
            val isConnected = status.type == ConnectionStatus.Type.CONNECTED
            binding.btnConnect.isEnabled = !isConnected
            binding.btnDisconnect.isEnabled = isConnected
        }

        viewModel.pairingCode.observe(this) { code ->
            if (code.isNotEmpty()) binding.etPairingCode.setText(code)
        }

        viewModel.serviceRunning.observe(this) { running ->
            binding.btnToggleService.text = if (running) "⏹ Stop Service" else "▶ Start Service"
        }

        viewModel.otpLog.observe(this) { logs ->
            binding.tvOtpLog.text = logs.takeLast(50).reversed().joinToString("\n") { entry ->
                "[${entry.timeStr}] OTP: ${entry.otp} | From: ${entry.sender}"
            }
        }

        viewModel.toastMessage.observe(this) { msg ->
            if (msg.isNotEmpty()) {
                Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()
                viewModel.clearToast()
            }
        }
    }

    // ─── Permissions ──────────────────────────────────────────────────────────
    private fun requestPermissionsIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            notifPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    private fun checkSmsPermissionsAndStart() {
        val permissions = arrayOf(Manifest.permission.RECEIVE_SMS, Manifest.permission.READ_SMS)
        val missing = permissions.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) startOtpService()
        else smsPermissionLauncher.launch(missing.toTypedArray())
    }

    // ─── Service control ──────────────────────────────────────────────────────
    private fun startOtpService() {
        val intent = Intent(this, OtpForwardingService::class.java).apply {
            putExtra("serverUrl", binding.etServerUrl.text.toString())
            putExtra("pairingCode", viewModel.pairingCode.value ?: "")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        viewModel.setServiceRunning(true)
    }

    private fun stopOtpService() {
        stopService(Intent(this, OtpForwardingService::class.java))
        viewModel.setServiceRunning(false)
    }

    private fun showSnackbar(msg: String) {
        Snackbar.make(binding.root, msg, Snackbar.LENGTH_SHORT).show()
    }
}
