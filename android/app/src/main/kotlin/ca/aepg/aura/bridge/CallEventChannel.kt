package ca.aepg.aura.bridge

import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telecom.Call
import android.telecom.DisconnectCause
import ca.aepg.aura.telecom.CallManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

/**
 * Streams live call lifecycle events to Flutter over the "aura/call_events" EventChannel.
 * The Dart side ([CallEventStream]) routes to the incoming / in-call screens and records
 * disconnect causes (#1 who-ended-the-call).
 *
 * Event payload (Map):
 *   { "type": "added"|"state"|"details"|"removed",
 *     "callId": String, "number": String?, "state": Int,
 *     "disconnectCode": Int?, "disconnectLabel": String? }
 */
object CallEventChannel {

    private const val CHANNEL = "aura/call_events"
    private val main = Handler(Looper.getMainLooper())

    // Multiple Flutter engines listen (the main app + the call UI), so broadcast to all
    // attached sinks instead of keeping a single one (which the call UI would otherwise steal).
    private val sinks = java.util.concurrent.CopyOnWriteArrayList<EventChannel.EventSink>()

    fun register(messenger: BinaryMessenger) {
        EventChannel(messenger, CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                private var local: EventChannel.EventSink? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    if (events == null) return
                    local = events
                    sinks.add(events)
                    // Replay current calls to THIS sink so a freshly-attached UI is in sync.
                    CallManager.all().forEach { (id, call) ->
                        main.post { events.success(base("added", id, call)) }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    local?.let { sinks.remove(it) }
                    local = null
                }
            },
        )
    }

    private fun emit(map: Map<String, Any?>) {
        for (s in sinks) main.post { s.success(map) }
    }

    fun emitCallAdded(id: String, call: Call) = emit(base("added", id, call))
    fun emitStateChange(id: String, call: Call) = emit(base("state", id, call))
    fun emitDetailsChange(id: String, call: Call) = emit(base("details", id, call))

    fun emitCallRemoved(id: String, call: Call, cause: DisconnectCause?) {
        emit(
            base("removed", id, call) + mapOf(
                "disconnectCode" to cause?.code,
                "disconnectLabel" to cause?.label?.toString(),
            ),
        )
    }

    private fun base(type: String, id: String, call: Call): Map<String, Any?> = mapOf(
        "type" to type,
        "callId" to id,
        "number" to call.details?.handle?.schemeSpecificPart,
        "state" to call.state,
        "name" to callerName(call),
        // Epoch ms the call connected (0 until connected) — drives the live in-call timer.
        "connectTimeMillis" to call.details?.connectTimeMillis,
    )

    /** Contact display name if Android resolved it, else CNAP caller-ID name. */
    private fun callerName(call: Call): String? {
        val details = call.details ?: return null
        val contact = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            details.contactDisplayName
        } else {
            null
        }
        return contact?.takeIf { it.isNotBlank() } ?: details.callerDisplayName?.takeIf { it.isNotBlank() }
    }
}
