package com.gehrig.g.ui

import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.gehrig.g.GApplication
import com.gehrig.g.R
import com.google.android.material.button.MaterialButton
import com.google.android.material.switchmaterial.SwitchMaterial
import com.google.android.material.textfield.TextInputEditText

class SettingsActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings)

        val app = GApplication.instance
        val prefs = app.prefs

        // API Key
        val apiKeyInput = findViewById<TextInputEditText>(R.id.apiKeyInput)
        val saveButton = findViewById<MaterialButton>(R.id.saveApiKeyButton)

        // Show current key (masked)
        val currentKey = app.claudeApiKey
        if (currentKey.isNotBlank()) {
            apiKeyInput.setText("••••••••${currentKey.takeLast(8)}")
        }

        saveButton.setOnClickListener {
            val key = apiKeyInput.text.toString().trim()
            if (key.isNotBlank() && !key.startsWith("••")) {
                app.claudeApiKey = key
                Toast.makeText(this, "API key saved", Toast.LENGTH_SHORT).show()
                apiKeyInput.setText("••••••••${key.takeLast(8)}")
            }
        }

        // Accessibility
        findViewById<MaterialButton>(R.id.enableAccessibilityButton).setOnClickListener {
            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
        }

        // Notification listener
        findViewById<MaterialButton>(R.id.enableNotificationsButton).setOnClickListener {
            startActivity(Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS"))
        }

        // Voice settings
        val wakeWordSwitch = findViewById<SwitchMaterial>(R.id.wakeWordSwitch)
        val voiceResponseSwitch = findViewById<SwitchMaterial>(R.id.voiceResponseSwitch)

        wakeWordSwitch.isChecked = prefs.getBoolean(GApplication.KEY_WAKE_WORD, false)
        voiceResponseSwitch.isChecked = prefs.getBoolean(GApplication.KEY_VOICE_RESPONSE, true)

        wakeWordSwitch.setOnCheckedChangeListener { _, isChecked ->
            prefs.edit().putBoolean(GApplication.KEY_WAKE_WORD, isChecked).apply()
        }

        voiceResponseSwitch.setOnCheckedChangeListener { _, isChecked ->
            prefs.edit().putBoolean(GApplication.KEY_VOICE_RESPONSE, isChecked).apply()
        }
    }
}
