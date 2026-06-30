package ca.aepg.aura.telecom

import android.telecom.Call
import android.telecom.DisconnectCause
import ca.aepg.aura.bridge.CallEventChannel
import ca.aepg.aura.bridge.EventLog
import java.util.concurrent.ConcurrentHashMap

/**
 * Process-wide registry of the currently tracked [Call]s. Owned conceptually by
 * [AuraInCallService] but kept as a singleton so the Flutter command channel
 * ([ca.aepg.aura.bridge.TelecomChannel]) can act on a call by id without holding a
 * service reference.
 *
 * Call ids are stable per-process strings derived from the Call object identity.
 */
object CallManager {

    private val calls = ConcurrentHashMap<String, Call>()
    private val callbacks = ConcurrentHashMap<String, Call.Callback>()

    fun idFor(call: Call): String = Integer.toHexString(System.identityHashCode(call))

    fun get(id: String): Call? = calls[id]

    fun all(): List<Pair<String, Call>> = calls.entries.map { it.key to it.value }

    /** The most relevant call for the ongoing-call notification (active > dialing > ringing > holding > any). */
    fun foreground(): Pair<String, Call>? {
        val entries = calls.entries.map { it.key to it.value }
        if (entries.isEmpty()) return null
        fun byState(state: Int) = entries.firstOrNull { it.second.state == state }
        return byState(Call.STATE_ACTIVE)
            ?: byState(Call.STATE_DIALING)
            ?: byState(Call.STATE_CONNECTING)
            ?: byState(Call.STATE_RINGING)
            ?: byState(Call.STATE_HOLDING)
            ?: entries.first()
    }

    fun onCallAdded(call: Call) {
        val id = idFor(call)
        calls[id] = call

        val cb = object : Call.Callback() {
            override fun onStateChanged(c: Call, state: Int) {
                CallEventChannel.emitStateChange(id, c)
            }

            override fun onDetailsChanged(c: Call, details: Call.Details) {
                CallEventChannel.emitDetailsChange(id, c)
            }
        }
        callbacks[id] = cb
        call.registerCallback(cb)

        CallEventChannel.emitCallAdded(id, call)
    }

    fun onCallRemoved(call: Call) {
        val id = idFor(call)
        // Feature #1 — who ended the call: read the disconnect cause at removal time.
        val cause: DisconnectCause? = call.details?.disconnectCause
        EventLog.recordDisconnect(id, call, cause)
        CallEventChannel.emitCallRemoved(id, call, cause)

        callbacks.remove(id)?.let { call.unregisterCallback(it) }
        calls.remove(id)
    }

    // --- Commands invoked from Flutter via TelecomChannel ---

    fun answer(id: String, videoState: Int = 0) {
        get(id)?.answer(videoState)
    }

    fun reject(id: String, withMessage: Boolean = false, message: String? = null) {
        get(id)?.reject(withMessage, message)
    }

    fun disconnect(id: String) {
        get(id)?.disconnect()
    }

    fun hold(id: String) = get(id)?.hold()
    fun unhold(id: String) = get(id)?.unhold()
    fun playDtmf(id: String, digit: Char) {
        get(id)?.let { it.playDtmfTone(digit); it.stopDtmfTone() }
    }
}
