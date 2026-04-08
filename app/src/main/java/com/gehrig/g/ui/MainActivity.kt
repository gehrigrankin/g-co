package com.gehrig.g.ui

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.IBinder
import android.provider.Settings
import android.text.TextUtils
import android.view.View
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.gehrig.g.R
import com.gehrig.g.accessibility.GAccessibilityService
import com.gehrig.g.notification.GNotificationListener
import com.gehrig.g.service.GAssistantService
import com.google.android.material.button.MaterialButton

/**
 * Main conversation UI for G.
 * Shows the chat history, input field, voice button, and status indicators.
 */
class MainActivity : AppCompatActivity() {

    private lateinit var conversationRecycler: RecyclerView
    private lateinit var messageInput: EditText
    private lateinit var sendButton: ImageButton
    private lateinit var voiceButton: ImageButton
    private lateinit var statusDot: View
    private lateinit var statusBanner: LinearLayout
    private lateinit var statusText: TextView
    private lateinit var enablePermissionsButton: MaterialButton
    private lateinit var settingsButton: ImageButton

    private lateinit var adapter: ConversationAdapter

    private var assistantService: GAssistantService? = null
    private var serviceBound = false

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            val localBinder = binder as GAssistantService.LocalBinder
            assistantService = localBinder.getService()
            serviceBound = true
            onServiceReady()
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            assistantService = null
            serviceBound = false
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        initViews()
        setupRecycler()
        setupInputHandlers()
        requestPermissions()

        // Start and bind to the assistant service
        GAssistantService.start(this)
        bindService(
            Intent(this, GAssistantService::class.java),
            serviceConnection,
            Context.BIND_AUTO_CREATE
        )
    }

    override fun onResume() {
        super.onResume()
        updatePermissionStatus()
    }

    override fun onDestroy() {
        if (serviceBound) {
            assistantService?.onMessageAdded = null
            assistantService?.onActionUpdate = null
            unbindService(serviceConnection)
            serviceBound = false
        }
        super.onDestroy()
    }

    private fun initViews() {
        conversationRecycler = findViewById(R.id.conversationRecycler)
        messageInput = findViewById(R.id.messageInput)
        sendButton = findViewById(R.id.sendButton)
        voiceButton = findViewById(R.id.voiceButton)
        statusDot = findViewById(R.id.statusDot)
        statusBanner = findViewById(R.id.statusBanner)
        statusText = findViewById(R.id.statusText)
        enablePermissionsButton = findViewById(R.id.enablePermissionsButton)
        settingsButton = findViewById(R.id.settingsButton)
    }

    private fun setupRecycler() {
        adapter = ConversationAdapter()
        conversationRecycler.layoutManager = LinearLayoutManager(this).apply {
            stackFromEnd = true
        }
        conversationRecycler.adapter = adapter
    }

    private fun setupInputHandlers() {
        // Send button
        sendButton.setOnClickListener {
            sendMessage()
        }

        // Enter key sends
        messageInput.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_SEND) {
                sendMessage()
                true
            } else false
        }

        // Voice button
        voiceButton.setOnClickListener {
            val service = assistantService ?: return@setOnClickListener
            if (service.voiceEngine.isListening) {
                service.voiceEngine.stopListening()
                voiceButton.alpha = 1.0f
            } else {
                service.voiceEngine.startListening()
                voiceButton.alpha = 0.5f // visual feedback that we're listening
            }
        }

        // Settings
        settingsButton.setOnClickListener {
            startActivity(Intent(this, SettingsActivity::class.java))
        }

        // Permission banner button
        enablePermissionsButton.setOnClickListener {
            if (!isAccessibilityEnabled()) {
                openAccessibilitySettings()
            } else if (!isNotificationListenerEnabled()) {
                openNotificationListenerSettings()
            }
        }
    }

    private fun sendMessage() {
        val text = messageInput.text.toString().trim()
        if (text.isEmpty()) return

        messageInput.text.clear()
        assistantService?.processUserInput(text)
    }

    private fun onServiceReady() {
        val service = assistantService ?: return

        // Load existing messages
        adapter.setMessages(service.messages)
        scrollToBottom()

        // Listen for new messages
        service.onMessageAdded = { message ->
            runOnUiThread {
                adapter.addMessage(message)
                scrollToBottom()
            }
        }

        // Listen for voice state changes
        service.voiceEngine.onListeningStateChanged = { listening ->
            runOnUiThread {
                voiceButton.alpha = if (listening) 0.5f else 1.0f
            }
        }
    }

    private fun scrollToBottom() {
        if (adapter.itemCount > 0) {
            conversationRecycler.smoothScrollToPosition(adapter.itemCount - 1)
        }
    }

    // ========================================================================
    // Permissions
    // ========================================================================

    private fun requestPermissions() {
        val permissions = mutableListOf<String>()
        val needed = arrayOf(
            Manifest.permission.RECORD_AUDIO,
            Manifest.permission.READ_CONTACTS,
            Manifest.permission.READ_SMS,
            Manifest.permission.READ_CALL_LOG,
            Manifest.permission.READ_CALENDAR,
            Manifest.permission.POST_NOTIFICATIONS
        )

        for (perm in needed) {
            if (ContextCompat.checkSelfPermission(this, perm) != PackageManager.PERMISSION_GRANTED) {
                permissions.add(perm)
            }
        }

        if (permissions.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, permissions.toTypedArray(), 100)
        }
    }

    private fun updatePermissionStatus() {
        val accessibilityOk = isAccessibilityEnabled()
        val notificationOk = isNotificationListenerEnabled()

        if (accessibilityOk && notificationOk) {
            statusBanner.visibility = View.GONE
            statusDot.setBackgroundColor(getColor(R.color.g_status_active))
        } else {
            statusBanner.visibility = View.VISIBLE
            statusDot.setBackgroundColor(getColor(R.color.g_status_inactive))

            val missing = mutableListOf<String>()
            if (!accessibilityOk) missing.add("Accessibility Service")
            if (!notificationOk) missing.add("Notification Access")
            statusText.text = "G needs: ${missing.joinToString(", ")}"
        }
    }

    private fun isAccessibilityEnabled(): Boolean {
        val service = "${packageName}/${GAccessibilityService::class.java.canonicalName}"
        val enabledServices = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        return enabledServices.contains(service)
    }

    private fun isNotificationListenerEnabled(): Boolean {
        val listeners = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners"
        ) ?: return false
        return listeners.contains(packageName)
    }

    private fun openAccessibilitySettings() {
        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
    }

    private fun openNotificationListenerSettings() {
        startActivity(Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS"))
    }
}
