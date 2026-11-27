package com.shehzad.finance_tracker

import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Hosts Flutter and answers the payment capture and backup folder channels. */
class MainActivity : FlutterFragmentActivity() {

    private val backupFolder = BackupFolder(this)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "finance_tracker/backup_folder")
            .setMethodCallHandler(backupFolder::handle)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "finance_tracker/capture")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isEnabled" -> result.success(isListenerEnabled())
                    "openSettings" -> {
                        openListenerSettings()
                        result.success(null)
                    }
                    "drain" -> result.success(PaymentNotificationListener.drain(this))
                    "getPackages" -> result.success(
                        if (PaymentNotificationListener.packagesChosen(this))
                            PaymentNotificationListener.allowedPackages(this).toList()
                        else null
                    )
                    "setPackages" -> {
                        val list = call.argument<List<String>>("packages").orEmpty()
                        PaymentNotificationListener.setAllowedPackages(this, list.toSet())
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Activity results still arrive here for startActivityForResult")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (!backupFolder.onActivityResult(requestCode, resultCode, data)) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    private val component get() = ComponentName(this, PaymentNotificationListener::class.java)

    private fun isListenerEnabled(): Boolean {
        val enabled = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: return false
        return enabled.split(":").any { ComponentName.unflattenFromString(it) == component }
    }

    /** Opens this app's notification access switch, or the full list where
     *  the direct screen is missing. */
    private fun openListenerSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS)
                .putExtra(Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME, component.flattenToString())
        } else {
            Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
        }
        try {
            startActivity(intent)
        } catch (e: ActivityNotFoundException) {
            startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
        }
    }
}
