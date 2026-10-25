package com.visabot.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.telephony.SmsMessage
import android.util.Log

/**
 * SmsReceiver - BroadcastReceiver for incoming SMS messages
 *
 * Responsibilities:
 * 1. Intercept all incoming SMS
 * 2. Filter for visa/OTP related messages using pattern matching
 * 3. Extract the OTP code from the message body
 * 4. Forward the OTP to OtpForwardingService
 */
class SmsReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "SmsReceiver"

        // ── OTP detection patterns ──────────────────────────────────────────────
        // These patterns identify SMS messages that contain OTPs for visa appointments
        val OTP_PATTERNS = listOf(
            // Visa / IVAC related senders
            Regex("ivac", RegexOption.IGNORE_CASE),
            Regex("vfs", RegexOption.IGNORE_CASE),
            Regex("visa", RegexOption.IGNORE_CASE),
            Regex("bls", RegexOption.IGNORE_CASE),
            // Generic OTP body patterns
            Regex("otp", RegexOption.IGNORE_CASE),
            Regex("one.?time.?password", RegexOption.IGNORE_CASE),
            Regex("verification.?code", RegexOption.IGNORE_CASE),
            Regex("your code is", RegexOption.IGNORE_CASE),
            Regex("use this code", RegexOption.IGNORE_CASE),
            Regex("do not share", RegexOption.IGNORE_CASE),
        )

        // Regex to extract numeric OTP codes (4-8 digits)
        val OTP_EXTRACTOR = Regex("\\b(\\d{4,8})\\b")

        // Senders that are explicitly visa-related (overrides body check)
        val TRUSTED_VISA_SENDERS = listOf("IVACBD", "IVAC", "VFSIND", "INDVISA", "BLS")

        /**
         * Extract OTP from SMS body text.
         * Returns the most likely OTP candidate (4-8 digit number).
         */
        fun extractOtp(body: String): String? {
            val matches = OTP_EXTRACTOR.findAll(body).toList()
            // Filter out years and obvious non-OTP numbers
            val candidates = matches.filter { m ->
                val n = m.value.toIntOrNull() ?: return@filter false
                n !in 1900..2100  // exclude years
            }
            // Prefer 6-digit codes (most common OTP length)
            return candidates.firstOrNull { it.value.length == 6 }?.value
                ?: candidates.firstOrNull { it.value.length in 4..8 }?.value
        }

        /**
         * Check if an SMS is visa/OTP related.
         */
        fun isVisaRelated(sender: String, body: String): Boolean {
            // Check trusted senders first
            if (TRUSTED_VISA_SENDERS.any { sender.contains(it, ignoreCase = true) }) return true
            // Check message body for OTP/visa keywords
            return OTP_PATTERNS.any { it.containsMatchIn(body) }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        val messages: Array<SmsMessage> = Telephony.Sms.Intents.getMessagesFromIntent(intent)

        for (sms in messages) {
            val sender = sms.displayOriginatingAddress ?: "UNKNOWN"
            val body = sms.messageBody ?: continue

            Log.d(TAG, "SMS received from: $sender")

            if (!isVisaRelated(sender, body)) {
                Log.d(TAG, "Not visa-related, ignoring")
                continue
            }

            val otp = extractOtp(body)
            if (otp == null) {
                Log.w(TAG, "Could not extract OTP from: $body")
                continue
            }

            Log.i(TAG, "Visa OTP detected: $otp from $sender")

            // Forward to the OtpForwardingService
            val serviceIntent = Intent(context, OtpForwardingService::class.java).apply {
                action = OtpForwardingService.ACTION_FORWARD_OTP
                putExtra("otp", otp)
                putExtra("rawMessage", body)
                putExtra("sender", sender)
            }
            context.startService(serviceIntent)
        }
    }
}
