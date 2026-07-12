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

    // Per-call start wall-clock (ms) and direction, stamped at add-time so the who-ended
    // queue (EventLog) can be matched to the system call log even with no Flutter engine.
    private val startTimes = ConcurrentHashMap<String, Long>()
    private val directions = ConcurrentHashMap<String, String>()

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
        startTimes[id] = System.currentTimeMillis()
        directions[id] = directionOf(call)

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
        // Queue who-ended data for the Flutter sidecar (matched to the system call log later).
        // connectTimeMillis is 0 when the call never connected (missed/rejected).
        EventLog.recordDisconnect(
            number = call.details?.handle?.schemeSpecificPart,
            causeCode = cause?.code ?: -1,
            startMillis = startTimes.remove(id) ?: System.currentTimeMillis(),
            connectMillis = call.details?.connectTimeMillis ?: 0L,
            endMillis = System.currentTimeMillis(),
            direction = directions.remove(id) ?: directionOf(call),
        )
        CallEventChannel.emitCallRemoved(id, call, cause)

        callbacks.remove(id)?.let { call.unregisterCallback(it) }
        calls.remove(id)
    }

    /** "incoming" | "outgoing" from the call direction (API 29+), falling back to state. */
    private fun directionOf(call: Call): String {
        val dir = call.details?.callDirection ?: Call.Details.DIRECTION_UNKNOWN
        return when (dir) {
            Call.Details.DIRECTION_INCOMING -> "incoming"
            Call.Details.DIRECTION_OUTGOING -> "outgoing"
            else -> if (call.state == Call.STATE_RINGING) "incoming" else "outgoing"
        }
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
