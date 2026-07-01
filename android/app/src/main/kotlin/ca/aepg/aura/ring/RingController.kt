package ca.aepg.aura.ring

import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import java.io.File
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.telecom.Call
import ca.aepg.aura.bridge.EventLog
import ca.aepg.aura.bridge.RulesSnapshot

/**
 * Owns ringtone + vibration playback for incoming calls. Because Aura is the default
 * dialer, the system does not auto-ring (our InCallService is responsible). This lets us:
 *
 *  - #5 force-ring even when the phone is silent  -> play on the ALARM stream, which is
 *       audible in silent/vibrate mode, plus a DND override when granted.
 *  - #8 intense mode                              -> ramp to max volume + strong vibration
 *       when the rules snapshot flags a repeat call (2 calls < 5 min).
 *  - normal calls                                 -> respect the system ringer mode.
 */
class RingController(private val context: Context) {

    private var ringtone: Ringtone? = null

    /** Alarm-stream volume to restore after a force/intense ring (null = nothing to restore). */
    private var savedAlarmVolume: Int? = null

    /** Interruption filter to restore after a DND override (null = nothing to restore). */
    private var prevInterruptionFilter: Int? = null

    private val audio: AudioManager
        get() = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private val notifications: NotificationManager
        get() = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    @Suppress("DEPRECATION")
    private val vibrator: Vibrator
        get() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }

    fun startRinging(call: Call) {
        val number = call.details?.handle?.schemeSpecificPart
        val snapshot = RulesSnapshot.read(context)
        // Evaluate before stamping so the intense check (#8) sees the *prior* call.
        val decision = number?.let { snapshot.evaluate(it, nowMinute(), today()) }
        if (number != null) EventLog.stampRecent(context, number, System.currentTimeMillis())

        val forceRing = decision?.forceRing == true
        val intense = decision?.intense == true
        val silent = audio.ringerMode != AudioManager.RINGER_MODE_NORMAL
        val custom = decision?.ringtoneUri // contact/group custom ringtone (else default)

        when {
            // Force-ring / intense: make it audible even in silent/vibrate/DND (needs DND access).
            intense -> ring(forceAudible = true, vibe = INTENSE_PATTERN, customUri = custom)
            forceRing && silent -> ring(forceAudible = true, vibe = NORMAL_PATTERN, customUri = custom)
            !silent -> ring(forceAudible = false, vibe = NORMAL_PATTERN, customUri = custom)
            audio.ringerMode == AudioManager.RINGER_MODE_VIBRATE -> vibrate(NORMAL_PATTERN)
            // RINGER_MODE_SILENT without force/intense: stay quiet.
        }
    }

    /**
     * Plays the ringtone. When [forceAudible] (force-ring / intense) it plays on the **alarm stream**
     * — which is audible in silent/vibrate without touching the ringer mode (so we never toggle DND)
     * — and raises the alarm volume, restored in [stop]. It also lifts an active DND if we have
     * access. Normal calls play on the ring stream and respect the system ringer.
     */
    private fun ring(forceAudible: Boolean, vibe: LongArray, customUri: String? = null) {
        val usage = if (forceAudible) {
            AudioAttributes.USAGE_ALARM
        } else {
            AudioAttributes.USAGE_NOTIFICATION_RINGTONE
        }
        if (forceAudible) {
            overrideDndIfPossible()
            runCatching {
                if (savedAlarmVolume == null) savedAlarmVolume = audio.getStreamVolume(AudioManager.STREAM_ALARM)
                audio.setStreamVolume(
                    AudioManager.STREAM_ALARM,
                    audio.getStreamMaxVolume(AudioManager.STREAM_ALARM),
                    0,
                )
            }
        }
        // Try the custom ringtone first; fall back to the system default on any failure.
        if (!startPlayer(customUri, usage)) startPlayer(null, usage)
        vibrate(vibe)
    }

    /**
     * Plays [customUri] (content:// or file path), or the system default, via the [Ringtone] player
     * — which opens system/OEM ringtone URIs reliably (unlike MediaPlayer.setDataSource, which fails
     * with status 0x80000000 on some OEMs). Returns false on failure so the caller can fall back.
     */
    private fun startPlayer(customUri: String?, usage: Int): Boolean {
        return try {
            val uri = when {
                customUri == null ->
                    RingtoneManager.getActualDefaultRingtoneUri(context, RingtoneManager.TYPE_RINGTONE)
                        ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                customUri.startsWith("content://") -> Uri.parse(customUri)
                else -> Uri.fromFile(File(customUri)) // audio file path
            } ?: return false

            val rt = RingtoneManager.getRingtone(context, uri) ?: return false
            rt.audioAttributes = AudioAttributes.Builder()
                .setUsage(usage)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                rt.isLooping = true
                runCatching { rt.volume = 1f }
            }
            rt.play()
            ringtone = rt
            true
        } catch (_: Exception) {
            runCatching { ringtone?.stop() }
            ringtone = null
            false
        }
    }

    private fun vibrate(pattern: LongArray) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(pattern, 0)
        }
    }

    /** Lift Do-Not-Disturb for the duration of a force/intense ring, if access was granted. */
    private fun overrideDndIfPossible() {
        if (prevInterruptionFilter != null) return // already overridden
        runCatching {
            if (notifications.isNotificationPolicyAccessGranted) {
                val current = notifications.currentInterruptionFilter
                if (current != NotificationManager.INTERRUPTION_FILTER_ALL) {
                    prevInterruptionFilter = current
                    notifications.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALL)
                }
            }
        }
    }

    fun stop() {
        ringtone?.run { runCatching { stop() } }
        ringtone = null
        vibrator.cancel()
        // Restore the alarm volume we raised for a force/intense ring.
        savedAlarmVolume?.let { v ->
            runCatching { audio.setStreamVolume(AudioManager.STREAM_ALARM, v, 0) }
            savedAlarmVolume = null
        }
        // Restore the user's Do-Not-Disturb state if we changed it.
        prevInterruptionFilter?.let { filter ->
            runCatching { notifications.setInterruptionFilter(filter) }
            prevInterruptionFilter = null
        }
    }

    private fun nowMinute(): Int {
        val c = java.util.Calendar.getInstance()
        return c.get(java.util.Calendar.HOUR_OF_DAY) * 60 + c.get(java.util.Calendar.MINUTE)
    }

    private fun today(): Int =
        java.util.Calendar.getInstance().get(java.util.Calendar.DAY_OF_WEEK) - 1

    companion object {
        private val NORMAL_PATTERN = longArrayOf(0, 1000, 1000)
        private val INTENSE_PATTERN = longArrayOf(0, 600, 200, 600, 200, 600, 200)
    }
}
