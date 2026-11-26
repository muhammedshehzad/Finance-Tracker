package com.shehzad.finance_tracker

import android.app.Notification
import android.content.Context
import android.util.Log
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONObject
import java.io.File

/**
 * Keeps payment notifications from the apps the user allowed (UPI apps, and
 * bank SMS if switched on) until the Flutter side collects them.
 *
 * Nothing else is stored: a notification must come from an allowed app and
 * mention an amount, and anything that looks like an OTP is dropped here,
 * before it is ever written to disk. Parsing and the user's confirmation
 * happen in Dart.
 */
class PaymentNotificationListener : NotificationListenerService() {

    /** Never throws: one odd notification must not stop the listener. */
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        try {
            if (!allowedPackages(this).contains(sbn.packageName)) return
            val extras = sbn.notification.extras ?: return
            if ((sbn.notification.flags and Notification.FLAG_GROUP_SUMMARY) != 0) return
            val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
            val text = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
                ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString().orEmpty()
            val all = "$title $text"
            if (!AMOUNT.containsMatchIn(all)) return
            if (OTP.containsMatchIn(all)) return

            val json = JSONObject()
                .put("key", "${sbn.key}|${all.hashCode()}")
                .put("package", sbn.packageName)
                .put("title", title)
                .put("text", text)
                .put("postedAt", sbn.postTime)
            append(this, json.toString())
        } catch (e: Exception) {
            Log.w(TAG, "Skipped a notification", e)
        }
    }

    companion object {
        private const val TAG = "PaymentCapture"
        private const val PREFS = "payment_capture"
        private const val KEY_PACKAGES = "packages"
        private const val FILE = "captured_notifications.jsonl"
        private const val MAX_LINES = 500
        private val lock = Any()

        private val AMOUNT = Regex("(₹|rs\\.?|inr)\\s*[0-9]|(debited|credited)\\s+(by|with|for)\\s+[0-9]", RegexOption.IGNORE_CASE)
        private val OTP = Regex("\\botp\\b|one[- ]time password|verification code", RegexOption.IGNORE_CASE)

        /** Google Pay, PhonePe, Paytm and BHIM, used until the user picks. */
        val DEFAULT_PACKAGES = setOf(
            "com.google.android.apps.nbu.paisa.user",
            "com.phonepe.app",
            "net.one97.paytm",
            "in.org.npci.upiapp",
        )

        /** Packages the listener reads from. */
        fun allowedPackages(context: Context): Set<String> =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getStringSet(KEY_PACKAGES, null) ?: DEFAULT_PACKAGES

        /** Whether the user has saved a choice yet. */
        fun packagesChosen(context: Context): Boolean =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).contains(KEY_PACKAGES)

        /** Saves the user's choice from the capture settings screen. */
        fun setAllowedPackages(context: Context, packages: Set<String>) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().putStringSet(KEY_PACKAGES, packages).apply()
        }

        /** Appends one JSON line, keeping only the newest [MAX_LINES]. */
        private fun append(context: Context, line: String): Unit = synchronized(lock) {
            val file = File(context.filesDir, FILE)
            file.appendText(line + "\n")
            val lines = file.readLines()
            if (lines.size > MAX_LINES) file.writeText(lines.takeLast(MAX_LINES).joinToString("\n", postfix = "\n"))
        }

        /** Returns everything stored so far and clears it. */
        fun drain(context: Context): List<String> {
            synchronized(lock) {
                val file = File(context.filesDir, FILE)
                if (!file.exists()) return emptyList()
                val lines = file.readLines().filter { it.isNotBlank() }
                file.delete()
                return lines
            }
        }
    }
}
