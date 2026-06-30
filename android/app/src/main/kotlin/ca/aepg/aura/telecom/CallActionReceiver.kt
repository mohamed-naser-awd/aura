package ca.aepg.aura.telecom

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Handles the ongoing-call notification's quick actions (see [CallNotification]).
 * Registered in the manifest, not exported — only Aura's own PendingIntents reach it.
 *
 *  - [ACTION_END]         → hang up the foreground call.
 *  - [ACTION_TOGGLE_MUTE] → flip the mic mute on the in-call service.
 *
 * (The "change device" action opens the call screen's picker directly via an Activity intent,
 * so it doesn't go through this receiver.)
 */
class CallActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_END -> CallManager.foreground()?.let { CallManager.disconnect(it.first) }
            ACTION_TOGGLE_MUTE -> {
                val svc = AuraInCallService.instance ?: return
                val muted = svc.currentAudioStateMap()?.get("muted") as? Boolean ?: false
                svc.applyMuted(!muted)
            }
        }
    }

    companion object {
        const val ACTION_END = "ca.aepg.aura.action.END_CALL"
        const val ACTION_TOGGLE_MUTE = "ca.aepg.aura.action.TOGGLE_MUTE"
    }
}
