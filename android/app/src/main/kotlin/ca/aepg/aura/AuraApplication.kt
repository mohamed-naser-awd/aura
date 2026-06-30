package ca.aepg.aura

import android.app.Application
import ca.aepg.aura.bridge.AudioStateChannel
import ca.aepg.aura.bridge.CallEventChannel
import ca.aepg.aura.bridge.TelecomChannel
import ca.aepg.aura.bridge.WhatsAppChannel
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugins.GeneratedPluginRegistrant

/**
 * Holds the process-wide [FlutterEngineGroup] and a **pre-warmed, cached** call-UI engine.
 *
 * The call window ([CallActivity]) attaches to this already-running engine, so it paints
 * immediately instead of showing black while a fresh engine cold-starts on every call.
 */
class AuraApplication : Application() {
    lateinit var engineGroup: FlutterEngineGroup
        private set

    companion object {
        const val CALL_ENGINE_ID = "aura_call_engine"
    }

    override fun onCreate() {
        super.onCreate()
        engineGroup = FlutterEngineGroup(this)
        prewarmCallEngine()
    }

    /** Spawn + run the minimal call UI now, register its channels, and cache it. */
    private fun prewarmCallEngine() {
        runCatching {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(this)
            loader.ensureInitializationComplete(this, null)

            val engine = engineGroup.createAndRunEngine(
                this,
                DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "callUiMain"),
            )
            // Register Flutter plugins so the call screen's in-app camera (camera/gal/
            // permission_handler) works; ActivityAware plugins bind when CallActivity attaches.
            GeneratedPluginRegistrant.registerWith(engine)

            val messenger = engine.dartExecutor.binaryMessenger
            // Register once now (no Activity needed for the call UI's telecom commands).
            TelecomChannel.register(this, messenger)
            CallEventChannel.register(messenger)
            AudioStateChannel.register(messenger)
            WhatsAppChannel.register(this, messenger)

            FlutterEngineCache.getInstance().put(CALL_ENGINE_ID, engine)
        }
    }
}
