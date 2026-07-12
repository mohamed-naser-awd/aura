package ca.aepg.aura.telecom

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.telecom.Call
import android.telecom.CallAudioState
import android.telecom.InCallService
import ca.aepg.aura.CallActivity
import ca.aepg.aura.ring.RingController
import java.util.concurrent.ConcurrentHashMap

/**
 * The default Phone app's in-call service. The OS binds to this for every call once
 * Aura holds ROLE_DIALER. Responsibilities:
 *  - track calls via [CallManager],
 *  - own ringing for incoming calls (force-ring when silent, intense mode) via [RingController],
 *  - launch the full-screen [CallActivity] UI,
 *  - show the ongoing-call notification ([CallNotification]) so the call screen is always reachable,
 *  - expose audio-route controls used by the in-call screen.
 */
class AuraInCallService : InCallService() {

    private val ring: RingController by lazy { RingController(applicationContext) }

    /** Per-call callback that starts/stops the ring as the call enters/leaves RINGING. */
    private val ringStoppers = ConcurrentHashMap<Call, Call.Callback>()

    /** Calls we've already started ringing for (avoids double-start across state changes). */
    private val ringingStarted = java.util.Collections.newSetFromMap(ConcurrentHashMap<Call, Boolean>())

    /** Per-call callback that keeps the ongoing-call notification in sync with call state. */
    private val notifCallbacks = ConcurrentHashMap<Call, Call.Callback>()

    private var foregroundStarted = false

    /** Number to dial once the current call fully disconnects (incoming "Call back" action). */
    @Volatile
    private var pendingCallbackNumber: String? = null

    /** Queue a callback: dial [number] once the line is free (see [onCallRemoved]). */
    fun scheduleCallback(number: String) {
        pendingCallbackNumber = number
    }

    override fun onCallAdded(call: Call) {
        super.onCallAdded(call)
        CallManager.onCallAdded(call)

        // Ring when the call is (or becomes) RINGING — some OEMs add the call *before* RINGING,
        // so we can't rely on the state at add-time.
        maybeStartRinging(call)
        val cb = object : Call.Callback() {
            override fun onStateChanged(c: Call, state: Int) {
                if (state == Call.STATE_RINGING) maybeStartRinging(c) else ring.stop()
            }
        }
        ringStoppers[call] = cb
        call.registerCallback(cb)

        // Keep the ongoing-call notification current as this call's state changes.
        val ncb = object : Call.Callback() {
            override fun onStateChanged(c: Call, state: Int) = updateNotification()
        }
        notifCallbacks[call] = ncb
        call.registerCallback(ncb)

        updateNotification()
        launchCallUi(call)
    }

    /** Start ringing once per call, only while it's actually RINGING. */
    private fun maybeStartRinging(call: Call) {
        if (call.state != Call.STATE_RINGING) return
        if (!ringingStarted.add(call)) return // already started for this call
        // Call waiting: another call is already up → don't blast our ringtone over it; the network
        // injects the call-waiting beep into the call audio instead.
        val hasOngoing = CallManager.all().any { (_, c) ->
            c !== call && (c.state == Call.STATE_ACTIVE || c.state == Call.STATE_HOLDING)
        }
        if (hasOngoing) return
        ring.startRinging(call)
    }

    override fun onCallRemoved(call: Call) {
        super.onCallRemoved(call)
        ring.stop()
        ringStoppers.remove(call)?.let { call.unregisterCallback(it) }
        notifCallbacks.remove(call)?.let { call.unregisterCallback(it) }
        ringingStarted.remove(call)
        CallManager.onCallRemoved(call)
        if (CallManager.all().isEmpty()) {
            val callback = pendingCallbackNumber
            if (callback != null) {
                // "Call back": the line is now free — dial the number (its onCallAdded repopulates
                // the window). Guard against a failed placeCall leaving a stuck empty window.
                pendingCallbackNumber = null
                runCatching { SimManager(applicationContext).placeCall(callback, null) }
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                    if (CallManager.all().isEmpty()) {
                        stopCallForeground()
                        CallActivity.instance?.finish()
                    }
                }, 8000)
            } else {
                // No calls left → drop the notification and close the (cached-engine) call window.
                stopCallForeground()
                CallActivity.instance?.finish()
            }
        } else {
            updateNotification()
        }
    }

    override fun onCallAudioStateChanged(audioState: CallAudioState) {
        super.onCallAudioStateChanged(audioState)
        ca.aepg.aura.bridge.AudioStateChannel.emit(currentAudioStateMap())
        updateNotification() // reflect mute / device label in the notification
    }

    /**
     * The OS calls this for the default dialer when the user presses a volume/power button while
     * a call is ringing. Silence our ring (audio + vibration) but leave the [Call] in RINGING so
     * answer/reject still work.
     */
    override fun onSilenceRinger() {
        super.onSilenceRinger()
        ring.stop()
    }

    /**
     * Silence the current ringtone/vibration if a call is ringing (key-event fallback for OEMs that
     * don't route volume keys through [onSilenceRinger]). Returns true if it silenced, so callers
     * only consume the key when something was actually ringing (never affects in-call volume).
     */
    fun silenceRingerIfRinging(): Boolean {
        val ringing = CallManager.all().any { it.second.state == Call.STATE_RINGING }
        if (ringing) ring.stop()
        return ringing
    }

    /** Called by [TelecomChannel] for the in-call screen's audio controls. */
    fun applyMuted(muted: Boolean) = setMuted(muted)
    fun applyAudioRoute(route: Int) = setAudioRoute(route)

    /** Current audio routing for the in-call device picker (null if no audio state yet). */
    fun currentAudioStateMap(): Map<String, Any?>? {
        val s = callAudioState ?: return null
        return mapOf(
            "route" to s.route,
            "supportedMask" to s.supportedRouteMask,
            "muted" to s.isMuted,
        )
    }

    /** Build/refresh the ongoing-call notification; promotes to foreground on the first call. */
    private fun updateNotification() {
        val fg = CallManager.foreground() ?: return
        val audio = callAudioState
        val muted = audio?.isMuted ?: false
        val route = audio?.route ?: CallAudioState.ROUTE_EARPIECE
        val notification = CallNotification.build(this, fg.first, fg.second, muted, route)
        if (!foregroundStarted) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                startForeground(
                    CallNotification.NOTIF_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL,
                )
            } else {
                startForeground(CallNotification.NOTIF_ID, notification)
            }
            foregroundStarted = true
        } else {
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .notify(CallNotification.NOTIF_ID, notification)
        }
    }

    private fun stopCallForeground() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        foregroundStarted = false
    }

    private fun launchCallUi(call: Call) {
        val route = if (call.state == Call.STATE_RINGING) "/incoming" else "/incall"
        val intent = Intent(this, CallActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            putExtra(CallActivity.EXTRA_CALL_ID, CallManager.idFor(call))
            putExtra(CallActivity.EXTRA_INITIAL_ROUTE, route)
        }
        startActivity(intent)
    }

    companion object {
        /** Set by the service so [TelecomChannel] can reach audio controls. */
        @Volatile
        var instance: AuraInCallService? = null
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        // Allow context-free callers (e.g. EventLog.recordDisconnect from CallManager) to persist.
        ca.aepg.aura.bridge.EventLog.appContext = applicationContext
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }
}
