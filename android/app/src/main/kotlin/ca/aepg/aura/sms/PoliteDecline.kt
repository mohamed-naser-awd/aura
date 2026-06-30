package ca.aepg.aura.sms

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.telephony.SmsManager
import androidx.core.content.ContextCompat

/**
 * Feature #9 — Polite Decline. When a group has polite-decline enabled, the screening
 * service rejects the call and we send the group's custom message via SMS.
 */
object PoliteDecline {

    private const val DEFAULT_MESSAGE = "Sorry, I can't take your call right now. I'll get back to you."

    fun send(context: Context, number: String, message: String?) {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.SEND_SMS) !=
            PackageManager.PERMISSION_GRANTED
        ) return

        val text = message?.takeIf { it.isNotBlank() } ?: DEFAULT_MESSAGE
        val sms = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            context.getSystemService(SmsManager::class.java)
        } else {
            @Suppress("DEPRECATION")
            SmsManager.getDefault()
        }
        runCatching {
            val parts = sms.divideMessage(text)
            sms.sendMultipartTextMessage(number, null, parts, null, null)
        }
    }
}
