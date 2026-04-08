package com.gehrig.g.notification

import android.app.Notification
import android.content.pm.PackageManager
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import com.gehrig.g.model.CapturedNotification

/**
 * G's notification awareness. This service intercepts all notifications
 * across all apps, letting G know about messages, emails, alerts, etc.
 * in real-time.
 */
class GNotificationListener : NotificationListenerService() {

    companion object {
        private const val TAG = "GNotificationListener"
        private const val MAX_HISTORY = 100

        var instance: GNotificationListener? = null
            private set

        val isRunning: Boolean get() = instance != null
    }

    /** Recent notifications G has seen */
    private val _notifications = mutableListOf<CapturedNotification>()
    val notifications: List<CapturedNotification> get() = _notifications.toList()

    /** Callback for real-time notification events */
    var onNotificationReceived: ((CapturedNotification) -> Unit)? = null
    var onNotificationRemoved: ((String) -> Unit)? = null

    override fun onListenerConnected() {
        super.onListenerConnected()
        instance = this
        Log.i(TAG, "G Notification Listener connected — G can now see all notifications")

        // Capture existing active notifications
        try {
            activeNotifications?.forEach { sbn ->
                val captured = parseNotification(sbn)
                if (captured != null) {
                    _notifications.add(captured)
                }
            }
            Log.i(TAG, "Captured ${_notifications.size} existing notifications")
        } catch (e: Exception) {
            Log.e(TAG, "Error capturing existing notifications", e)
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        sbn ?: return
        val captured = parseNotification(sbn) ?: return

        _notifications.add(0, captured)
        if (_notifications.size > MAX_HISTORY) {
            _notifications.removeAt(_notifications.lastIndex)
        }

        Log.d(TAG, "Notification from ${captured.appName}: ${captured.title} — ${captured.text}")
        onNotificationReceived?.invoke(captured)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        sbn ?: return
        val key = sbn.key
        _notifications.removeAll { it.key == key }
        onNotificationRemoved?.invoke(key)
    }

    override fun onListenerDisconnected() {
        instance = null
        Log.i(TAG, "G Notification Listener disconnected")
        super.onListenerDisconnected()
    }

    // ========================================================================
    // Query methods for the AI brain
    // ========================================================================

    /** Get all notifications from a specific app */
    fun getNotificationsFrom(packageName: String): List<CapturedNotification> =
        _notifications.filter { it.packageName == packageName }

    /** Get notifications that likely contain messages (SMS, messaging apps) */
    fun getMessageNotifications(): List<CapturedNotification> {
        val messagingApps = setOf(
            "com.google.android.apps.messaging",   // Google Messages
            "com.samsung.android.messaging",         // Samsung Messages
            "com.whatsapp",
            "org.telegram.messenger",
            "com.facebook.orca",                     // Messenger
            "com.discord",
            "com.Slack",
            "com.instagram.android",
            "com.snapchat.android",
            "com.twitter.android",
        )
        return _notifications.filter { it.packageName in messagingApps }
    }

    /** Get notifications that are likely emails */
    fun getEmailNotifications(): List<CapturedNotification> {
        val emailApps = setOf(
            "com.google.android.gm",               // Gmail
            "com.microsoft.office.outlook",
            "com.yahoo.mobile.client.android.mail",
            "me.bluemail.mail",
        )
        return _notifications.filter { it.packageName in emailApps }
    }

    /** Get a text summary of recent notifications for the AI */
    fun describeNotifications(): String = buildString {
        appendLine("=== NOTIFICATIONS (${_notifications.size} total) ===")
        if (_notifications.isEmpty()) {
            appendLine("No notifications.")
            return@buildString
        }
        _notifications.take(20).forEachIndexed { i, notif ->
            appendLine("[$i] ${notif.appName}: ${notif.title ?: "(no title)"}")
            notif.text?.let { appendLine("    $it") }
        }
    }

    /** Dismiss a notification by key */
    fun dismiss(key: String) {
        cancelNotification(key)
    }

    // ========================================================================
    // Internal
    // ========================================================================

    private fun parseNotification(sbn: StatusBarNotification): CapturedNotification? {
        val notification = sbn.notification ?: return null
        val extras = notification.extras ?: return null

        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
            ?: extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()

        // Skip empty or system notifications
        if (title == null && text == null) return null

        val appName = try {
            val appInfo = packageManager.getApplicationInfo(sbn.packageName, 0)
            packageManager.getApplicationLabel(appInfo).toString()
        } catch (e: PackageManager.NameNotFoundException) {
            sbn.packageName
        }

        return CapturedNotification(
            packageName = sbn.packageName,
            appName = appName,
            title = title,
            text = text,
            timestamp = sbn.postTime,
            key = sbn.key
        )
    }
}
