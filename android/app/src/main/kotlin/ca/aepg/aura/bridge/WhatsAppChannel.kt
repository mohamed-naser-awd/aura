package ca.aepg.aura.bridge

import android.content.ContentProviderOperation
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.ContactsContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * WhatsApp quick-action bridge ("aura/whatsapp"). Backs the Dart `WhatsAppService`.
 *
 * Methods:
 *   isInstalled()      -> Bool      whether com.whatsapp or com.whatsapp.w4b is present
 *   openChat(number)   -> opens a WhatsApp chat for the number (wa.me link)
 *   whatsAppNumbers()  -> List<String> digit-normalized numbers of WhatsApp-synced contacts
 *                         (used only by "contacts only" mode; needs READ_CONTACTS)
 */
object WhatsAppChannel {

    private const val CHANNEL = "aura/whatsapp"
    private val PACKAGES = listOf("com.whatsapp", "com.whatsapp.w4b")
    private const val WA_PROFILE_MIME = "vnd.android.cursor.item/vnd.com.whatsapp.profile"

    /** Tag stored in RawContacts.SOURCE_ID so probe contacts are always identifiable for cleanup. */
    private const val PROBE_TAG = "aura_wa_probe"

    private val mainHandler = Handler(Looper.getMainLooper())

    fun register(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isInstalled" -> result.success(installedPackage(app) != null)
                "openChat" -> {
                    openChat(app, call.argument<String>("number") ?: "")
                    result.success(true)
                }
                "whatsAppNumbers" -> result.success(whatsAppNumbers(app))
                "scanNumbers" -> {
                    val numbers = call.argument<List<String>>("numbers") ?: emptyList()
                    val timeoutMs = (call.argument<Int>("timeoutMs") ?: 30000).toLong()
                    // Inserts + polling + deletes off the main thread; reply when done.
                    Thread {
                        val res = runCatching { scanNumbers(app, numbers, timeoutMs) }
                            .getOrDefault(emptyMap())
                        mainHandler.post { result.success(res) }
                    }.start()
                }
                "cleanupProbes" -> {
                    cleanupProbeContacts(app)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * The opt-in probe: temporarily add each number as a LOCAL-ONLY contact (never synced to
     * the cloud), let WhatsApp's contact-change sync add its profile rows, read which numbers
     * gained a WhatsApp profile, then delete the temporary contacts.
     *
     * Best-effort: WhatsApp sync timing is not guaranteed, so a number on WhatsApp may read
     * false if sync hasn't run within [timeoutMs]; the caller re-scans later and caches results.
     * Returns number -> hasWhatsApp for every input number.
     */
    private fun scanNumbers(context: Context, numbers: List<String>, timeoutMs: Long): Map<String, Boolean> {
        if (numbers.isEmpty()) return emptyMap()
        cleanupProbeContacts(context) // clear any leftovers from a previous interrupted run
        numbers.forEach { insertProbeContact(context, it) }

        val targets = numbers.associateWith { normalizeForWa(it) }
        val found = mutableSetOf<String>()
        val deadline = SystemClock.elapsedRealtime() + timeoutMs
        try {
            while (SystemClock.elapsedRealtime() < deadline && found.size < targets.size) {
                Thread.sleep(2000)
                val current = whatsAppNumbers(context)
                for ((_, t) in targets) {
                    if (t.isNotEmpty() && current.any { suffixMatch(it, t) }) found.add(t)
                }
            }
        } catch (_: InterruptedException) {
            // fall through to cleanup
        } finally {
            cleanupProbeContacts(context)
        }
        return targets.mapValues { (_, t) -> found.contains(t) }
    }

    private fun insertProbeContact(context: Context, number: String) {
        val ops = ArrayList<ContentProviderOperation>()
        // RawContact in the local ("device") account so it is never synced to any cloud.
        ops.add(
            ContentProviderOperation.newInsert(ContactsContract.RawContacts.CONTENT_URI)
                .withValue(ContactsContract.RawContacts.ACCOUNT_TYPE, null)
                .withValue(ContactsContract.RawContacts.ACCOUNT_NAME, null)
                .withValue(ContactsContract.RawContacts.SOURCE_ID, PROBE_TAG)
                .build(),
        )
        ops.add(
            ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
                .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
                .withValue(
                    ContactsContract.Data.MIMETYPE,
                    ContactsContract.CommonDataKinds.StructuredName.CONTENT_ITEM_TYPE,
                )
                .withValue(ContactsContract.CommonDataKinds.StructuredName.DISPLAY_NAME, "Aura probe")
                .build(),
        )
        ops.add(
            ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
                .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
                .withValue(
                    ContactsContract.Data.MIMETYPE,
                    ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE,
                )
                .withValue(ContactsContract.CommonDataKinds.Phone.NUMBER, number)
                .withValue(
                    ContactsContract.CommonDataKinds.Phone.TYPE,
                    ContactsContract.CommonDataKinds.Phone.TYPE_MOBILE,
                )
                .build(),
        )
        runCatching { context.contentResolver.applyBatch(ContactsContract.AUTHORITY, ops) }
    }

    private fun cleanupProbeContacts(context: Context) {
        runCatching {
            context.contentResolver.delete(
                ContactsContract.RawContacts.CONTENT_URI,
                "${ContactsContract.RawContacts.SOURCE_ID} = ?",
                arrayOf(PROBE_TAG),
            )
        }
    }

    /** True if two digit-strings share the same trailing 9 digits (loose match). */
    private fun suffixMatch(a: String, b: String): Boolean {
        if (a.isEmpty() || b.isEmpty()) return false
        val sa = a.takeLast(9)
        val sb = b.takeLast(9)
        return sa == sb
    }

    private fun installedPackage(context: Context): String? {
        val pm = context.packageManager
        return PACKAGES.firstOrNull { pkg ->
            try {
                pm.getPackageInfo(pkg, 0)
                true
            } catch (_: PackageManager.NameNotFoundException) {
                false
            }
        }
    }

    private fun openChat(context: Context, rawNumber: String) {
        val digits = normalizeForWa(rawNumber)
        if (digits.isEmpty()) return
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://wa.me/$digits")).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            installedPackage(context)?.let { setPackage(it) }
        }
        try {
            context.startActivity(intent)
        } catch (_: Exception) {
            // Fall back to no explicit package (lets the system resolve / show chooser).
            context.startActivity(
                Intent(Intent.ACTION_VIEW, Uri.parse("https://wa.me/$digits"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }
    }

    private fun whatsAppNumbers(context: Context): List<String> {
        val numbers = mutableSetOf<String>()
        val resolver = context.contentResolver
        val cursor: Cursor? = resolver.query(
            ContactsContract.Data.CONTENT_URI,
            arrayOf(ContactsContract.Data.DATA1, ContactsContract.Data.DATA3),
            "${ContactsContract.Data.MIMETYPE} = ?",
            arrayOf(WA_PROFILE_MIME),
            null,
        )
        cursor?.use { c ->
            val data1 = c.getColumnIndex(ContactsContract.Data.DATA1)
            val data3 = c.getColumnIndex(ContactsContract.Data.DATA3)
            while (c.moveToNext()) {
                val candidate = (c.takeIf { data1 >= 0 }?.getString(data1))
                    ?: (c.takeIf { data3 >= 0 }?.getString(data3))
                val n = candidate?.let { normalizeForWa(it) }
                if (!n.isNullOrEmpty()) numbers.add(n)
            }
        }
        return numbers.toList()
    }

    /** Digits only; drop a leading "00" (international prefix). WhatsApp wa.me wants no '+'. */
    private fun normalizeForWa(raw: String): String {
        var digits = raw.filter { it.isDigit() }
        if (digits.startsWith("00")) digits = digits.substring(2)
        return digits
    }
}
