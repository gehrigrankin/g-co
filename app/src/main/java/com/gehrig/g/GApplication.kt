package com.gehrig.g

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.SharedPreferences
import android.os.Build

class GApplication : Application() {

    lateinit var prefs: SharedPreferences
        private set

    override fun onCreate() {
        super.onCreate()
        instance = this
        prefs = getSharedPreferences("g_prefs", Context.MODE_PRIVATE)
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        val channel = NotificationChannel(
            CHANNEL_ASSISTANT,
            getString(R.string.notification_channel_name),
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = getString(R.string.notification_channel_description)
            setShowBadge(false)
        }

        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.createNotificationChannel(channel)
    }

    var claudeApiKey: String
        get() {
            // First check SharedPreferences (user-entered), then fall back to BuildConfig
            val saved = prefs.getString(KEY_API_KEY, null)
            if (!saved.isNullOrBlank()) return saved
            return BuildConfig.CLAUDE_API_KEY
        }
        set(value) {
            prefs.edit().putString(KEY_API_KEY, value).apply()
        }

    val isVoiceResponseEnabled: Boolean
        get() = prefs.getBoolean(KEY_VOICE_RESPONSE, true)

    val isWakeWordEnabled: Boolean
        get() = prefs.getBoolean(KEY_WAKE_WORD, false)

    companion object {
        lateinit var instance: GApplication
            private set

        const val CHANNEL_ASSISTANT = "g_assistant"
        const val KEY_API_KEY = "claude_api_key"
        const val KEY_VOICE_RESPONSE = "voice_response"
        const val KEY_WAKE_WORD = "wake_word"
    }
}
