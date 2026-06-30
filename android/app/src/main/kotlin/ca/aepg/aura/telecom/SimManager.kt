package ca.aepg.aura.telecom

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.telephony.SubscriptionInfo
import android.telephony.SubscriptionManager
import androidx.core.content.ContextCompat

/**
 * Enumerates the device's call-capable SIM accounts and places outgoing calls on a
 * chosen SIM. Supports features #5 (long-press SIM selector) and #6/#7 (per-group /
 * per-call default SIM).
 */
class SimManager(private val context: Context) {

    private val telecom: TelecomManager
        get() = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager

    data class SimAccount(
        val id: String,        // PhoneAccountHandle flattened to a stable string
        val label: String,
        val isDefault: Boolean,
        val carrierName: String?,
        val slotIndex: Int,    // 0-based; -1 if unknown
    )

    private fun hasPhonePermission(): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.READ_PHONE_STATE) ==
            PackageManager.PERMISSION_GRANTED

    fun listSimAccounts(): List<SimAccount> {
        if (!hasPhonePermission()) return emptyList()
        val handles = telecom.callCapablePhoneAccounts
        val default = telecom.getDefaultOutgoingPhoneAccount(PhoneAccount.SCHEME_TEL)
        val subs = activeSubscriptions()
        return handles.mapNotNull { handle ->
            val account = telecom.getPhoneAccount(handle) ?: return@mapNotNull null
            val sub = matchSubscription(handle, subs)
            SimAccount(
                id = encode(handle),
                label = account.label?.toString() ?: handle.id,
                isDefault = handle == default,
                carrierName = sub?.carrierName?.toString()
                    ?: sub?.displayName?.toString()
                    ?: account.label?.toString(),
                slotIndex = sub?.simSlotIndex ?: -1,
            )
        }
    }

    private fun activeSubscriptions(): List<SubscriptionInfo> {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.READ_PHONE_STATE) !=
            PackageManager.PERMISSION_GRANTED
        ) return emptyList()
        val sm = context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE)
            as? SubscriptionManager ?: return emptyList()
        return try {
            sm.activeSubscriptionInfoList ?: emptyList()
        } catch (_: SecurityException) {
            emptyList()
        }
    }

    /** Telephony SIM PhoneAccountHandle.id is usually the subscription id as a string. */
    private fun matchSubscription(
        handle: PhoneAccountHandle,
        subs: List<SubscriptionInfo>,
    ): SubscriptionInfo? {
        val subId = handle.id.toIntOrNull()
        return subs.firstOrNull { it.subscriptionId == subId }
            ?: subs.firstOrNull { handle.id.contains(it.subscriptionId.toString()) }
    }

    /** Places a call on [phoneAccountId] (a SIM). If null, the system default is used. */
    fun placeCall(number: String, phoneAccountId: String?) {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CALL_PHONE) !=
            PackageManager.PERMISSION_GRANTED
        ) return

        val uri = Uri.fromParts(PhoneAccount.SCHEME_TEL, number, null)
        val extras = Bundle()
        phoneAccountId?.let { id ->
            decode(id)?.let { handle ->
                extras.putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, handle)
            }
        }
        telecom.placeCall(uri, extras)
    }

    private fun encode(handle: PhoneAccountHandle): String =
        "${handle.componentName.flattenToString()}|${handle.id}"

    private fun decode(id: String): PhoneAccountHandle? {
        val parts = id.split("|", limit = 2)
        if (parts.size != 2) return null
        val component = android.content.ComponentName.unflattenFromString(parts[0]) ?: return null
        return PhoneAccountHandle(component, parts[1])
    }
}
