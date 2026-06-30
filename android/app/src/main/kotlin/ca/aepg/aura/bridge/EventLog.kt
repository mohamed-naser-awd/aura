package ca.aepg.aura.bridge

import android.content.Context
import android.telecom.Call
import android.telecom.DisconnectCause
import org.json.JSONArray
import org.json.JSONObject

/**
 * Native-side persistence of call events. Two jobs:
 *
 *  1. Track recent incoming-call timestamps per number so [RulesSnapshot] can detect the
 *     "2 calls within 5 minutes" condition for intense mode (#8) — even when the Flutter
 *     engine is not running.
 *  2. Queue disconnect events (who-ended, #1) so the Flutter app can ingest them on next
 *     launch, in addition to the live [CallEventChannel] stream.
 */
object EventLog {

    private const val PREFS = "aura_events"
    private const val KEY_RECENT = "recent_incoming"   // map number -> last timestamp
    private const val KEY_QUEUE = "disconnect_queue"   // JSON array pending Flutter ingest

    fun stampRecent(context: Context, number: String, nowMs: Long) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val map = runCatching { JSONObject(prefs.getString(KEY_RECENT, "{}") ?: "{}") }
            .getOrElse { JSONObject() }
        map.put(normalize(number), nowMs)
        prefs.edit().putString(KEY_RECENT, map.toString()).apply()
    }

    /**
     * True if a prior call from [number] arrived within [windowMs] before [nowMs].
     * Stamp the current arrival with [stampRecent] *after* this check.
     */
    fun hadRecentCall(context: Context, number: String, windowMs: Long, nowMs: Long): Boolean {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val map = runCatching { JSONObject(prefs.getString(KEY_RECENT, "{}") ?: "{}") }
            .getOrElse { JSONObject() }
        val last = map.optLong(normalize(number), 0L)
        return last != 0L && (nowMs - last) <= windowMs
    }

    fun recordDisconnect(callId: String, call: Call, cause: DisconnectCause?) {
        val ctx = appContext ?: return
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val arr = runCatching { JSONArray(prefs.getString(KEY_QUEUE, "[]") ?: "[]") }
            .getOrElse { JSONArray() }
        arr.put(
            JSONObject().apply {
                put("callId", callId)
                put("number", call.details?.handle?.schemeSpecificPart)
                put("cause", cause?.code ?: -1)
                put("label", cause?.label?.toString())
            },
        )
        prefs.edit().putString(KEY_QUEUE, arr.toString()).apply()
    }

    /** Set once from Application/Service so context-free callers can persist. */
    @Volatile
    var appContext: Context? = null

    private fun normalize(number: String): String = number.filter { it.isDigit() || it == '+' }
}
