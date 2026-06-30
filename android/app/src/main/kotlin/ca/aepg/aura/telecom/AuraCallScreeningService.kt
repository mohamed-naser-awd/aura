package ca.aepg.aura.telecom

import android.telecom.Call
import android.telecom.CallScreeningService
import ca.aepg.aura.bridge.RulesSnapshot
import ca.aepg.aura.sms.PoliteDecline

/**
 * Pre-ring decision engine. The OS invokes this for incoming (and outgoing) calls before
 * ringing, while the Flutter UI may not be running — so all decisions are made in native
 * code against the [RulesSnapshot] that Flutter exports on every rule change.
 *
 * Implements features:
 *  - #3 mute incoming from a muted group              -> setSilenceCall
 *  - #4 time-window rule (ring until 22:00 then mute) -> setSilenceCall when outside window
 *  - #8 intense mode trigger (2 calls < 5 min)        -> flag carried to RingController via EventLog
 *  - #9 polite-decline auto-SMS                       -> setRejectCall + PoliteDecline.send
 */
class AuraCallScreeningService : CallScreeningService() {

    override fun onScreenCall(callDetails: Call.Details) {
        val number = callDetails.handle?.schemeSpecificPart
        val incoming = callDetails.callDirection == Call.Details.DIRECTION_INCOMING

        val builder = CallResponse.Builder()

        if (incoming && number != null) {
            val snapshot = RulesSnapshot.read(applicationContext)
            val decision = snapshot.evaluate(number, nowMinuteOfDay(), todayDayOfWeek())
            // NOTE: the arrival timestamp for intense detection (#8) is stamped later by
            // RingController, so its "2 calls < 5 min" check compares against the prior call.

            when {
                decision.blocked -> {
                    // Reject silently and keep it out of notifications.
                    builder.setDisallowCall(true)
                        .setRejectCall(true)
                        .setSkipNotification(true)
                }
                decision.politeDecline -> {
                    builder.setDisallowCall(true)
                        .setRejectCall(true)
                        .setSkipCallLog(false)
                        .setSkipNotification(false)
                    PoliteDecline.send(applicationContext, number, decision.politeDeclineMessage)
                }
                decision.shouldMute -> {
                    // Silence ringing but still show the call / log it.
                    builder.setSilenceCall(true)
                }
                else -> {
                    // Allow normally; RingController (in the InCallService) applies
                    // force-ring / intense escalation if decision.forceRing/intense set.
                }
            }
        }

        respondToCall(callDetails, builder.build())
    }

    private fun nowMinuteOfDay(): Int {
        val c = java.util.Calendar.getInstance()
        return c.get(java.util.Calendar.HOUR_OF_DAY) * 60 + c.get(java.util.Calendar.MINUTE)
    }

    private fun todayDayOfWeek(): Int {
        // 0 = Sunday .. 6 = Saturday (matches Dart DateTime mapping used in the snapshot).
        return java.util.Calendar.getInstance().get(java.util.Calendar.DAY_OF_WEEK) - 1
    }
}
