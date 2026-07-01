package ca.aepg.aura.bridge

import android.app.Activity
import android.app.NotificationManager
import android.app.role.RoleManager
import android.content.Context
import android.content.Intent
import android.os.Build
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
 */
object TelecomChannel {

    private const val CHANNEL = "aura/telecom"
    const val REQUEST_DIALER_ROLE = 4201

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
