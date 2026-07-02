package ca.aepg.aura.telecom

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.telecom.Call
import android.telecom.CallAudioState
import ca.aepg.aura.CallActivity

/**
 * Builds the ongoing-call notification shown while a call exists, so the user can always get
 * back to the call screen (tap the body) and act on the call without it (End / Mute / change
 * audio device). The notification is silent — [RingController] owns ringing.
 */
object CallNotification {

    const val CHANNEL_ID = "aura_calls"
    const val NOTIF_ID = 42

    private const val REQ_CONTENT = 0
    private const val REQ_END = 1
    private const val REQ_MUTE = 2
    private const val REQ_AUDIO = 3

    fun ensureChannel(context: Context) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Ongoing calls",
            NotificationManager.IMPORTANCE_LOW, // silent; ringing is handled separately
        ).apply {
            description = "Controls for the active call"
            setSound(null, null)
            enableVibration(false)
            setShowBadge(false)
        }
        nm.createNotificationChannel(channel)
    }

    fun build(context: Context, callId: String, call: Call, muted: Boolean, route: Int): Notification {
        ensureChannel(context)

        val endIntent = broadcast(context, REQ_END, CallActionReceiver.ACTION_END)
        val muteAction = action(
            context,
            if (muted) android.R.drawable.ic_lock_silent_mode else android.R.drawable.ic_lock_silent_mode_off,
            if (muted) "Unmute" else "Mute",
            broadcast(context, REQ_MUTE, CallActionReceiver.ACTION_TOGGLE_MUTE),
        )
        val deviceAction = action(
            context, android.R.drawable.stat_sys_speakerphone, "Device",
            openCallScreen(context, REQ_AUDIO, openAudioPicker = true),
        )

        val builder = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.sym_action_call)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_CALL)
            .setOnlyAlertOnce(true)
            .setContentIntent(openCallScreen(context, REQ_CONTENT, openAudioPicker = false))

        // Live, self-ticking call timer once connected (Android updates it — no per-second reposts).
        val connected = call.details?.connectTimeMillis ?: 0L
        val ticking = connected > 0L &&
            (call.state == Call.STATE_ACTIVE || call.state == Call.STATE_HOLDING)
        if (ticking) {
            builder.setWhen(connected).setShowWhen(true).setUsesChronometer(true)
        } else {
            builder.setShowWhen(false)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // CallStyle is non-dismissible while the call is ongoing (unlike a plain FGS
            // notification, which is user-swipeable since Android 13). Its hang-up button IS "End".
            val person = Person.Builder().setName(title(call)).build()
            builder
                .setStyle(Notification.CallStyle.forOngoingCall(person, endIntent))
                .addAction(muteAction)
                .addAction(deviceAction)
        } else {
            // API 29–30: FGS notifications are already non-dismissible; use a plain layout.
            builder
                .setContentTitle(title(call))
                .setContentText("${statusText(call.state)} · ${routeLabel(route)}")
                .addAction(
                    action(context, android.R.drawable.ic_menu_close_clear_cancel, "End", endIntent),
                )
                .addAction(muteAction)
                .addAction(deviceAction)
        }
        return builder.build()
    }

    private fun action(context: Context, iconRes: Int, label: CharSequence, pi: PendingIntent) =
        Notification.Action.Builder(Icon.createWithResource(context, iconRes), label, pi).build()

    /** Tap → bring the call screen to the front; optionally ask the call UI to open the audio picker. */
    private fun openCallScreen(context: Context, requestCode: Int, openAudioPicker: Boolean): PendingIntent {
        val intent = Intent(context, CallActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (openAudioPicker) putExtra(CallActivity.EXTRA_OPEN_AUDIO_PICKER, true)
        }
        return PendingIntent.getActivity(context, requestCode, intent, immutableFlags(update = true))
    }

    private fun broadcast(context: Context, requestCode: Int, action: String): PendingIntent {
        val intent = Intent(context, CallActionReceiver::class.java).setAction(action)
        return PendingIntent.getBroadcast(context, requestCode, intent, immutableFlags(update = false))
    }

    private fun immutableFlags(update: Boolean): Int {
        var flags = PendingIntent.FLAG_IMMUTABLE
        if (update) flags = flags or PendingIntent.FLAG_UPDATE_CURRENT
        return flags
    }

    private fun title(call: Call): String {
        val details = call.details
        val name = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            details?.contactDisplayName
        } else {
            null
        }
        return name?.takeIf { it.isNotBlank() }
            ?: details?.callerDisplayName?.takeIf { it.isNotBlank() }
            ?: details?.handle?.schemeSpecificPart
            ?: "Unknown"
    }

    private fun statusText(state: Int): String = when (state) {
        Call.STATE_RINGING -> "Incoming call"
        Call.STATE_DIALING, Call.STATE_CONNECTING -> "Dialing"
        Call.STATE_HOLDING -> "On hold"
        Call.STATE_ACTIVE -> "On call"
        else -> "In call"
    }

    private fun routeLabel(route: Int): String = when (route) {
        CallAudioState.ROUTE_SPEAKER -> "Speaker"
        CallAudioState.ROUTE_BLUETOOTH -> "Bluetooth"
        CallAudioState.ROUTE_WIRED_HEADSET -> "Wired headset"
        else -> "Earpiece"
    }
}
