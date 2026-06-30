package ca.aepg.aura

import android.app.Activity
import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import ca.aepg.aura.bridge.CallEventChannel
import ca.aepg.aura.bridge.RulesSnapshot
import ca.aepg.aura.bridge.TelecomChannel
import ca.aepg.aura.bridge.WhatsAppChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter UI and registers Aura's platform channels, plus the system ringtone
 * picker ("aura/pickers") which needs an Activity + onActivityResult.
 */
class MainActivity : FlutterActivity() {

    private companion object {
        const val PICKERS_CHANNEL = "aura/pickers"
        const val REQUEST_RINGTONE = 4301
    }

    private var pendingRingtoneResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        TelecomChannel.register(this, messenger, this)
        CallEventChannel.register(messenger)
        RulesSnapshot.registerWriter(this, messenger)
        WhatsAppChannel.register(this, messenger)

        MethodChannel(messenger, PICKERS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickSystemRingtone" -> {
                    pendingRingtoneResult = result
                    val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
                        putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_RINGTONE)
                        putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
                        putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
                        putExtra(RingtoneManager.EXTRA_RINGTONE_TITLE, "Select ringtone")
                        val existing = call.argument<String>("current")
                        if (existing != null) {
                            putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI, Uri.parse(existing))
                        }
                    }
                    startActivityForResult(intent, REQUEST_RINGTONE)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_RINGTONE) {
            val result = pendingRingtoneResult
            pendingRingtoneResult = null
            if (result == null) return
            if (resultCode == Activity.RESULT_OK) {
                val uri: Uri? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    data?.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    data?.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
                }
                // null picked URI = the "Default" entry; use a sentinel so Flutter can tell
                // it apart from a cancel.
                result.success(uri?.toString() ?: "__default__")
            } else {
                result.success(null) // cancelled
            }
        }
    }
}
