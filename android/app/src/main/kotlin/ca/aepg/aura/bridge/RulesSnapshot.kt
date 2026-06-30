package ca.aepg.aura.bridge

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * The native-readable, denormalized copy of the user's groups + rules. Flutter exports
 * this via the "aura/rules" method channel on every change (see registerWriter); the
 * telephony services read it synchronously without needing the Flutter engine alive.
 *
 * Snapshot JSON shape:
 * {
 *   "version": 1,
 *   "intenseScope": "group" | "all",
 *   "members": { "<e164Number>": "<groupId>" },
 *   "groups": {
 *     "<groupId>": {
 *       "muteEnabled": bool,
 *       "forceRing": bool,            // ring even when silent
 *       "intenseModeEnabled": bool,
 *       "politeDeclineEnabled": bool,
 *       "politeDeclineMessage": "..",
 *       "rules": [ { "kind": "ringWindow"|"mute", "start": int, "end": int, "days": int } ]
 *     }
 *   }
 * }
 */
object RulesSnapshot {

    private const val PREFS = "aura_rules"
    private const val KEY_JSON = "snapshot_json"
    private const val CHANNEL = "aura/rules"

    data class Decision(
        val groupId: String? = null,
        val blocked: Boolean = false,
        val shouldMute: Boolean = false,
        val forceRing: Boolean = false,
        val intense: Boolean = false,
        val politeDecline: Boolean = false,
        val politeDeclineMessage: String? = null,
        /** Custom ringtone (content:// URI or file path) to play; null = default. */
        val ringtoneUri: String? = null,
    )

    fun registerWriter(context: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "exportSnapshot" -> {
                    val json = call.argument<String>("json") ?: "{}"
                    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                        .edit().putString(KEY_JSON, json).apply()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun load(context: Context): JSONObject {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_JSON, "{}") ?: "{}"
        return runCatching { JSONObject(raw) }.getOrElse { JSONObject() }
    }

    /** Read the snapshot wrapped for evaluation. */
    fun read(context: Context): Evaluator = Evaluator(load(context), context)

    class Evaluator(private val root: JSONObject, private val context: Context) {

        fun evaluate(number: String, minuteOfDay: Int, dayOfWeek: Int): Decision {
            if (isBlocked(number)) return Decision(blocked = true)
            val normalized = normalize(number)
            // A per-contact ringtone applies regardless of group membership.
            val contactRingtone = lookupContactRingtone(number)
            val members = root.optJSONObject("members")
            val groupId = members?.let { findGroupId(it, number) }
            if (groupId == null) return Decision(ringtoneUri = contactRingtone)
            val group = root.optJSONObject("groups")?.optJSONObject(groupId)
                ?: return Decision(ringtoneUri = contactRingtone)

            var mute = group.optBoolean("muteEnabled", false)
            val forceRing = group.optBoolean("forceRing", false)

            // #4 time-window rules: outside a ringWindow => mute.
            val rules = group.optJSONArray("rules")
            if (rules != null) {
                for (i in 0 until rules.length()) {
                    val r = rules.optJSONObject(i) ?: continue
                    if (!appliesToday(r.optInt("days", 0x7F), dayOfWeek)) continue
                    val start = r.optInt("start", 0)
                    val end = r.optInt("end", 24 * 60)
                    val inside = minuteOfDay in start until end
                    when (r.optString("kind")) {
                        "ringWindow" -> if (!inside) mute = true
                        "mute" -> if (inside) mute = true
                    }
                }
            }

            // #8 intense: enabled for the group and a prior call arrived < 5 min ago.
            val intense = group.optBoolean("intenseModeEnabled", false) &&
                EventLog.hadRecentCall(context, normalized, INTENSE_WINDOW_MS, System.currentTimeMillis())

            val politeDecline = group.optBoolean("politeDeclineEnabled", false)
            val groupRingtone = if (group.isNull("ringtone")) null else group.optString("ringtone", null)

            return Decision(
                groupId = groupId,
                shouldMute = mute && !forceRing, // force-ring overrides mute
                forceRing = forceRing,
                intense = intense,
                politeDecline = politeDecline,
                politeDeclineMessage = group.optString("politeDeclineMessage", null),
                ringtoneUri = contactRingtone ?: groupRingtone, // contact overrides group
            )
        }

        /** Per-number custom ringtone from the snapshot's `ringtones` map (suffix match). */
        private fun lookupContactRingtone(number: String): String? {
            val map = root.optJSONObject("ringtones") ?: return null
            val target = suffix(number)
            if (target.isEmpty()) return null
            val keys = map.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                if (suffix(key) == target) return map.optString(key, null)
            }
            return null
        }

        private fun appliesToday(daysMask: Int, dayOfWeek: Int): Boolean =
            (daysMask shr dayOfWeek) and 1 == 1

        private fun normalize(number: String): String = number.filter { it.isDigit() || it == '+' }

        /**
         * Match the incoming number against member keys by trailing digits (last 9), so a
         * locally-saved number (e.g. 01001234567) matches the incoming E.164 (+201001234567).
         */
        private fun findGroupId(members: JSONObject, number: String): String? {
            val target = suffix(number)
            if (target.isEmpty()) return null
            val keys = members.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                if (suffix(key) == target) return members.optString(key, null)
            }
            return null
        }

        private fun suffix(s: String): String {
            val d = s.filter { it.isDigit() }
            return if (d.length <= 9) d else d.substring(d.length - 9)
        }

        private fun isBlocked(number: String): Boolean {
            val arr = root.optJSONArray("blocked") ?: return false
            val target = suffix(number)
            if (target.isEmpty()) return false
            for (i in 0 until arr.length()) {
                if (suffix(arr.optString(i)) == target) return true
            }
            return false
        }
    }

    private const val INTENSE_WINDOW_MS = 5 * 60 * 1000L
}
