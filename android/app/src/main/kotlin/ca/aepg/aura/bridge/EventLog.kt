package ca.aepg.aura.bridge

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Native-side persistence of call events. Two jobs:
 *
 *  1. Track recent incoming-call timestamps per number so [RulesSnapshot] can detect the
 *     "2 calls within 5 minutes" condition for intense mode (#8) — even when the Flutter
 *     engine is not running.
 *  2. Queue disconnect events (who-ended, #1) so the Flutter app can ingest them into its
 *     "who-ended" sidecar. This fires from the InCallService in whatever engine is alive
 *     (including with the main Flutter engine dead), so it is the reliable who-ended source;
 *     the drain happens on the next Recents open via [takeQueue].
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

    /**
     * Queue one witnessed call's who-ended data for the Flutter sidecar. Timestamps are
     * epoch-ms; [connectMillis] is 0 when the call never connected (missed/rejected).
     * [direction] is "incoming" | "outgoing".
     */
    fun recordDisconnect(
        number: String?,
        causeCode: Int,
        startMillis: Long,
        connectMillis: Long,
        endMillis: Long,
        direction: String,
    ) {
        val ctx = appContext ?: return
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val arr = runCatching { JSONArray(prefs.getString(KEY_QUEUE, "[]") ?: "[]") }
            .getOrElse { JSONArray() }
        arr.put(
            JSONObject().apply {
                put("number", number)
                put("cause", causeCode)
                put("startMillis", startMillis)
                put("connectMillis", connectMillis)
                put("endMillis", endMillis)
                put("direction", direction)
            },
        )
        prefs.edit().putString(KEY_QUEUE, arr.toString()).apply()
    }

    /** Read and clear the pending disconnect queue in one edit. Returns the queued entries. */
    fun takeQueue(context: Context): List<Map<String, Any?>> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val arr = runCatching { JSONArray(prefs.getString(KEY_QUEUE, "[]") ?: "[]") }
            .getOrElse { JSONArray() }
        prefs.edit().putString(KEY_QUEUE, "[]").apply()
        return (0 until arr.length()).mapNotNull { i ->
            val o = arr.optJSONObject(i) ?: return@mapNotNull null
            mapOf(
                "number" to o.opt("number")?.takeIf { it != JSONObject.NULL },
                "cause" to o.optInt("cause", -1),
                "startMillis" to o.optLong("startMillis", 0L),
                "connectMillis" to o.optLong("connectMillis", 0L),
                "endMillis" to o.optLong("endMillis", 0L),
                "direction" to o.optString("direction", "incoming"),
            )
        }
    }

    /** Set once from Application/Service so context-free callers can persist. */
    @Volatile
    var appContext: Context? = null

    private fun normalize(number: String): String = number.filter { it.isDigit() || it == '+' }
}
