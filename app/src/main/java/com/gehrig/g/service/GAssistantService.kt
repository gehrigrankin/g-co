package com.gehrig.g.service

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Binder
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.gehrig.g.GApplication
import com.gehrig.g.R
import com.gehrig.g.ai.GBrain
import com.gehrig.g.controller.PhoneController
import com.gehrig.g.model.ConversationMessage
import com.gehrig.g.model.Role
import com.gehrig.g.ui.MainActivity
import com.gehrig.g.voice.VoiceEngine
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Foreground service that keeps G alive and ready.
 * This is the backbone — it owns the Brain, VoiceEngine, and PhoneController,
 * and runs as a persistent foreground service so Android doesn't kill G.
 */
class GAssistantService : Service() {

    companion object {
        private const val TAG = "GAssistantService"
        private const val NOTIFICATION_ID = 1

        var instance: GAssistantService? = null
            private set

        val isRunning: Boolean get() = instance != null

        fun start(context: Context) {
            val intent = Intent(context, GAssistantService::class.java)
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            val intent = Intent(context, GAssistantService::class.java)
            context.stopService(intent)
        }
    }

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    lateinit var voiceEngine: VoiceEngine
        private set
    lateinit var phoneController: PhoneController
        private set
    lateinit var brain: GBrain
        private set

    /** Conversation history for the UI */
    private val _messages = mutableListOf<ConversationMessage>()
    val messages: List<ConversationMessage> get() = _messages.toList()

    /** UI callback for new messages */
    var onMessageAdded: ((ConversationMessage) -> Unit)? = null
    var onActionUpdate: ((String) -> Unit)? = null

    private var isProcessing = false

    inner class LocalBinder : Binder() {
        fun getService(): GAssistantService = this@GAssistantService
    }

    private val binder = LocalBinder()

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onCreate() {
        super.onCreate()
        instance = this

        // Initialize components
        voiceEngine = VoiceEngine(this)
        voiceEngine.initialize()

        phoneController = PhoneController(this, voiceEngine)
        brain = GBrain(phoneController)

        // Wire up voice input
        voiceEngine.onSpeechResult = { text ->
            processUserInput(text)
        }

        // Wire up action updates from brain to UI
        brain.onActionUpdate = { action ->
            onActionUpdate?.invoke(action)
        }

        // Add greeting
        val greeting = ConversationMessage(
            role = Role.ASSISTANT,
            text = getString(R.string.g_greeting)
        )
        _messages.add(greeting)

        Log.i(TAG, "G Assistant Service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification())
        Log.i(TAG, "G is now running in the foreground")
        return START_STICKY
    }

    override fun onDestroy() {
        instance = null
        voiceEngine.shutdown()
        serviceScope.cancel()
        Log.i(TAG, "G Assistant Service destroyed")
        super.onDestroy()
    }

    /**
     * Process user input (from text or voice).
     */
    fun processUserInput(text: String) {
        if (isProcessing) {
            Log.w(TAG, "Already processing a request, ignoring: $text")
            return
        }

        // Add user message
        val userMsg = ConversationMessage(role = Role.USER, text = text)
        _messages.add(userMsg)
        onMessageAdded?.invoke(userMsg)

        isProcessing = true

        serviceScope.launch {
            try {
                val response = brain.processRequest(text)
                _messages.add(response)
                onMessageAdded?.invoke(response)

                // Speak the response if voice is enabled
                if (GApplication.instance.isVoiceResponseEnabled) {
                    voiceEngine.speak(response.text)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error processing request", e)
                val errorMsg = ConversationMessage(
                    role = Role.ASSISTANT,
                    text = "Something went wrong. ${e.message}"
                )
                _messages.add(errorMsg)
                onMessageAdded?.invoke(errorMsg)
            } finally {
                isProcessing = false
            }
        }
    }

    private fun buildNotification(): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, GApplication.CHANNEL_ASSISTANT)
            .setContentTitle("G is active")
            .setContentText("Listening and ready to help")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setSilent(true)
            .build()
    }
}
