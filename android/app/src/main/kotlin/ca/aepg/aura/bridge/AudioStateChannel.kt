package ca.aepg.aura.bridge

import android.os.Handler
import android.os.Looper
import ca.aepg.aura.telecom.AuraInCallService
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Streams the in-call audio routing state (current route, supported routes, mute) to the
 * call UI over the "aura/audio" EventChannel so the device picker reflects live changes
 * (e.g. plugging a headset, connecting Bluetooth).
 *
 * Payload: { "route": Int, "supportedMask": Int, "muted": Bool }
 */
object AudioStateChannel {

    private const val CHANNEL = "aura/audio"
    private val main = Handler(Looper.getMainLooper())
    private val sinks = CopyOnWriteArrayList<EventChannel.EventSink>()

    fun register(messenger: BinaryMessenger) {
        EventChannel(messenger, CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                private var local: EventChannel.EventSink? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    if (events == null) return
                    local = events
                    sinks.add(events)
                    AuraInCallService.instance?.currentAudioStateMap()?.let { state ->
                        main.post { events.success(state) }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    local?.let { sinks.remove(it) }
                    local = null
                }
            },
        )
    }

    fun emit(state: Map<String, Any?>?) {
        if (state == null) return
        for (s in sinks) main.post { s.success(state) }
    }
}
