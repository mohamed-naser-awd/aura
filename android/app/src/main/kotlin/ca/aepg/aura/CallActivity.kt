package ca.aepg.aura

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import ca.aepg.aura.bridge.AudioStateChannel
import ca.aepg.aura.bridge.CallEventChannel
import ca.aepg.aura.bridge.TelecomChannel
import ca.aepg.aura.bridge.WhatsAppChannel
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Full-screen incoming/in-call UI. Launched by [ca.aepg.aura.telecom.AuraInCallService]
 * when a call is added. Attaches to the **pre-warmed cached** engine
 * ([AuraApplication.CALL_ENGINE_ID]) so it paints immediately (no black cold-start). If the
 * cached engine is somehow missing, it falls back to spawning one from the engine group.
 *
 * The cached engine is shared/reused, so it is NOT destroyed with this activity; native
 * ([AuraInCallService]) finishes the activity when the last call ends.
 */
class CallActivity : FlutterActivity() {

    companion object {
        const val EXTRA_CALL_ID = "ca.aepg.aura.CALL_ID"
        const val EXTRA_INITIAL_ROUTE = "ca.aepg.aura.INITIAL_ROUTE"
        const val EXTRA_OPEN_AUDIO_PICKER = "ca.aepg.aura.OPEN_AUDIO_PICKER"
        private const val CALL_UI_CHANNEL = "aura/call_ui"

        /** The live call window, so native can finish it when calls end. */
        @Volatile
        var instance: CallActivity? = null
    }

    private fun hasCached(): Boolean =
        FlutterEngineCache.getInstance().contains(AuraApplication.CALL_ENGINE_ID)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        instance = this
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
        maybeOpenAudioPicker(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        maybeOpenAudioPicker(intent)
    }

    /** The notification's "change device" action deep-links here; ask the call UI to open the picker. */
    private fun maybeOpenAudioPicker(intent: Intent?) {
        if (intent?.getBooleanExtra(EXTRA_OPEN_AUDIO_PICKER, false) != true) return
        val engine = FlutterEngineCache.getInstance().get(AuraApplication.CALL_ENGINE_ID) ?: return
        MethodChannel(engine.dartExecutor.binaryMessenger, CALL_UI_CHANNEL)
            .invokeMethod("openAudioPicker", null)
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    /** Prefer the pre-warmed cached engine (channels already registered at warm time). */
    override fun getCachedEngineId(): String? =
        if (hasCached()) AuraApplication.CALL_ENGINE_ID else null

    override fun shouldDestroyEngineWithHost(): Boolean = !hasCached()

    /** Fallback only: cache miss → spawn the call engine from the group and register channels. */
    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        if (hasCached()) return null
        val group = (applicationContext as AuraApplication).engineGroup
        val bundle = FlutterInjector.instance().flutterLoader().findAppBundlePath()
        val engine = group.createAndRunEngine(this, DartExecutor.DartEntrypoint(bundle, "callUiMain"))
        io.flutter.plugins.GeneratedPluginRegistrant.registerWith(engine)
        val messenger = engine.dartExecutor.binaryMessenger
        TelecomChannel.register(this, messenger, this)
        CallEventChannel.register(messenger)
        AudioStateChannel.register(messenger)
        WhatsAppChannel.register(this, messenger)
        return engine
    }
}
