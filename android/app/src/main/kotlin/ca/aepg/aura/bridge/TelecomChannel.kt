package ca.aepg.aura.bridge

import android.app.Activity
import android.app.NotificationManager
import android.app.role.RoleManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.CallLog
import android.provider.Settings
import ca.aepg.aura.telecom.AuraInCallService
import ca.aepg.aura.telecom.CallManager
import ca.aepg.aura.telecom.SimManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter -> native command channel ("aura/telecom"). Backs the Dart `TelecomService`.
 *
 * Methods:
 *   isDefaultDialer()                       -> Bool
 *   requestDefaultDialerRole()              -> launches the system role dialog
 *   getSimAccounts()                        -> List<Map> {id,label,isDefault}
 *   placeCall(number, phoneAccountId?)
 *   answer(callId) / reject(callId,message?) / end(callId)
 *   hold(callId) / unhold(callId) / dtmf(callId, digit)
 *   setMuted(muted) / setAudioRoute(route)
 *   getSystemCallLog(limit, sinceMillis?)   -> List<Map> from content://call_log (Recents source)
 *   takeDisconnectQueue()                    -> List<Map> read-and-clear who-ended sidecar queue
 */
object TelecomChannel {

    private const val CHANNEL = "aura/telecom"
    const val REQUEST_DIALER_ROLE = 4201

    private val mainHandler = Handler(Looper.getMainLooper())

    /**
     * [activity] is only needed for the default-dialer role flow (main app). The call-UI
     * engine registers with a null activity — it only uses answer/reject/end/mute/route/dtmf.
     */
    fun register(context: Context, messenger: BinaryMessenger, activity: Activity? = null) {
        val sim = SimManager(context.applicationContext)

        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isDefaultDialer" -> result.success(isDefaultDialer(context))
                "requestDefaultDialerRole" -> {
                    activity?.let { requestDialerRole(it) }
                    result.success(true)
                }
                "getSimAccounts" -> result.success(
                    sim.listSimAccounts().map {
                        mapOf(
                            "id" to it.id,
                            "label" to it.label,
                            "isDefault" to it.isDefault,
                            "carrierName" to it.carrierName,
                            "slotIndex" to it.slotIndex,
                        )
                    },
                )
                "placeCall" -> {
                    sim.placeCall(
                        call.argument<String>("number")!!,
                        call.argument<String>("phoneAccountId"),
                    )
                    result.success(true)
                }
                "answer" -> { CallManager.answer(call.argument<String>("callId")!!); result.success(true) }
                "reject" -> {
                    CallManager.reject(
                        call.argument<String>("callId")!!,
                        call.argument<String>("message") != null,
                        call.argument<String>("message"),
                    )
                    result.success(true)
                }
                "end" -> { CallManager.disconnect(call.argument<String>("callId")!!); result.success(true) }
                "hold" -> { CallManager.hold(call.argument<String>("callId")!!); result.success(true) }
                "unhold" -> { CallManager.unhold(call.argument<String>("callId")!!); result.success(true) }
                "dtmf" -> {
                    CallManager.playDtmf(
                        call.argument<String>("callId")!!,
                        call.argument<String>("digit")!!.first(),
                    )
                    result.success(true)
                }
                "setMuted" -> {
                    AuraInCallService.instance?.applyMuted(call.argument<Boolean>("muted") == true)
                    result.success(true)
                }
                "setAudioRoute" -> {
                    AuraInCallService.instance?.applyAudioRoute(call.argument<Int>("route")!!)
                    result.success(true)
                }
                "blockNumber" -> {
                    RulesSnapshot.addPendingBlock(context, call.argument<String>("number")!!)
                    result.success(true)
                }
                "callBack" -> {
                    // Reject the ringing call and dial the number once the line is free.
                    AuraInCallService.instance?.scheduleCallback(call.argument<String>("number")!!)
                    CallManager.reject(call.argument<String>("callId")!!)
                    result.success(true)
                }
                "getSystemCallLog" -> {
                    val limit = call.argument<Int>("limit") ?: 200
                    val since = call.argument<Number>("sinceMillis")?.toLong()
                    // Query off the main thread; the call-log cursor can be large.
                    Thread {
                        val rows = runCatching { querySystemCallLog(context, limit, since) }
                            .getOrElse { emptyList() }
                        mainHandler.post { result.success(rows) }
                    }.start()
                }
                "takeDisconnectQueue" -> result.success(EventLog.takeQueue(context))
                "hasDndAccess" -> {
                    val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    result.success(nm.isNotificationPolicyAccessGranted)
                }
                "openDndAccessSettings" -> {
                    context.startActivity(
                        Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * The device's system call log (the single source of truth for which calls exist).
     * Returns the most-recent [limit] rows, newest first, optionally only those after
     * [sinceMillis]. Each map: id, number, type (CallLog.Calls.TYPE), date (epoch ms = start),
     * duration (talk seconds), cachedName.
     */
    private fun querySystemCallLog(context: Context, limit: Int, sinceMillis: Long?): List<Map<String, Any?>> {
        val projection = arrayOf(
            CallLog.Calls._ID,
            CallLog.Calls.NUMBER,
            CallLog.Calls.TYPE,
            CallLog.Calls.DATE,
            CallLog.Calls.DURATION,
            CallLog.Calls.CACHED_NAME,
        )
        val selection = sinceMillis?.let { "${CallLog.Calls.DATE} > ?" }
        val args = sinceMillis?.let { arrayOf(it.toString()) }
        val out = ArrayList<Map<String, Any?>>()
        context.contentResolver.query(
            CallLog.Calls.CONTENT_URI,
            projection,
            selection,
            args,
            "${CallLog.Calls.DATE} DESC",
        )?.use { c ->
            val iId = c.getColumnIndex(CallLog.Calls._ID)
            val iNum = c.getColumnIndex(CallLog.Calls.NUMBER)
            val iType = c.getColumnIndex(CallLog.Calls.TYPE)
            val iDate = c.getColumnIndex(CallLog.Calls.DATE)
            val iDur = c.getColumnIndex(CallLog.Calls.DURATION)
            val iName = c.getColumnIndex(CallLog.Calls.CACHED_NAME)
            while (c.moveToNext() && out.size < limit) {
                out.add(
                    mapOf(
                        "id" to c.getLong(iId),
                        "number" to c.getString(iNum),
                        "type" to c.getInt(iType),
                        "date" to c.getLong(iDate),
                        "duration" to c.getInt(iDur),
                        "cachedName" to (if (iName >= 0) c.getString(iName) else null),
                    ),
                )
            }
        }
        return out
    }

    private fun isDefaultDialer(context: Context): Boolean {
        val rm = context.getSystemService(Context.ROLE_SERVICE) as RoleManager
        return rm.isRoleHeld(RoleManager.ROLE_DIALER)
    }

    private fun requestDialerRole(activity: Activity) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val rm = activity.getSystemService(Context.ROLE_SERVICE) as RoleManager
            if (rm.isRoleAvailable(RoleManager.ROLE_DIALER) && !rm.isRoleHeld(RoleManager.ROLE_DIALER)) {
                val intent: Intent = rm.createRequestRoleIntent(RoleManager.ROLE_DIALER)
                activity.startActivityForResult(intent, REQUEST_DIALER_ROLE)
            }
        }
    }
}
