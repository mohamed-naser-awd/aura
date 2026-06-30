package ca.aepg.aura.ring

import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
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

    private var player: MediaPlayer? = null

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
            intense -> ring(streamAlarm = true, maxVolume = true, vibe = INTENSE_PATTERN, customUri = custom)
            // Raise the alarm volume so force-ring is actually audible in silent mode.
            forceRing && silent -> ring(streamAlarm = true, maxVolume = true, vibe = NORMAL_PATTERN, customUri = custom)
            !silent -> ring(streamAlarm = false, maxVolume = false, vibe = NORMAL_PATTERN, customUri = custom)
            audio.ringerMode == AudioManager.RINGER_MODE_VIBRATE -> vibrate(NORMAL_PATTERN)
            // RINGER_MODE_SILENT without force/intense: stay quiet.
        }
    }

    private fun ring(streamAlarm: Boolean, maxVolume: Boolean, vibe: LongArray, customUri: String? = null) {
        if (streamAlarm) overrideDndIfPossible()
        val usage = if (streamAlarm) AudioAttributes.USAGE_ALARM else AudioAttributes.USAGE_NOTIFICATION_RINGTONE
        // Try the custom ringtone first; fall back to the system default on any failure.
        if (!startPlayer(customUri, usage)) startPlayer(null, usage)
        if (maxVolume) {
            val stream = if (streamAlarm) AudioManager.STREAM_ALARM else AudioManager.STREAM_RING
            runCatching { audio.setStreamVolume(stream, audio.getStreamMaxVolume(stream), 0) }
        }
        vibrate(vibe)
    }

    /** Starts the looping player with [customUri] (content:// or file path), or the default. */
    private fun startPlayer(customUri: String?, usage: Int): Boolean {
        return try {
            player = MediaPlayer().apply {
                if (customUri != null && !customUri.startsWith("content://")) {
                    setDataSource(customUri) // audio file path
                } else {
                    val uri = customUri?.let { android.net.Uri.parse(it) }
                        ?: RingtoneManager.getActualDefaultRingtoneUri(context, RingtoneManager.TYPE_RINGTONE)
                        ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                    setDataSource(context, uri)
                }
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(usage)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                isLooping = true
                prepare()
                start()
            }
            true
        } catch (_: Exception) {
            player?.run { runCatching { release() } }
            player = null
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
        player?.run { runCatching { stop() }; release() }
        player = null
        vibrator.cancel()
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
