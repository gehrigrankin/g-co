package com.gehrig.g.controller

import android.content.Context
import android.content.Intent
import android.util.Log
import com.gehrig.g.accessibility.GAccessibilityService
import com.gehrig.g.model.PhoneAction
import com.gehrig.g.model.ScrollDirection
import com.gehrig.g.voice.VoiceEngine
import kotlinx.coroutines.delay

/**
 * Executes phone actions planned by GBrain.
 * This is the bridge between AI decisions and actual phone control.
 */
class PhoneController(
    private val context: Context,
    private val voiceEngine: VoiceEngine
) {

    companion object {
        private const val TAG = "PhoneController"
    }

    private val accessibility: GAccessibilityService?
        get() = GAccessibilityService.instance

    /**
     * Execute a single phone action.
     */
    suspend fun execute(action: PhoneAction): Boolean {
        Log.d(TAG, "Executing action: $action")

        return when (action) {
            is PhoneAction.Tap -> {
                val service = accessibility ?: return logNoService()
                service.tapNode(action.nodeIndex)
            }

            is PhoneAction.TapCoordinates -> {
                val service = accessibility ?: return logNoService()
                service.tapAtCoordinates(action.x, action.y)
            }

            is PhoneAction.TypeText -> {
                val service = accessibility ?: return logNoService()
                service.typeText(action.nodeIndex, action.text)
            }

            is PhoneAction.Scroll -> {
                val service = accessibility ?: return logNoService()
                val forward = action.direction == ScrollDirection.DOWN ||
                              action.direction == ScrollDirection.RIGHT
                service.scroll(action.nodeIndex, forward)
            }

            is PhoneAction.LaunchApp -> {
                launchApp(action.packageName)
            }

            is PhoneAction.GoBack -> {
                val service = accessibility ?: return logNoService()
                service.pressBack()
            }

            is PhoneAction.GoHome -> {
                val service = accessibility ?: return logNoService()
                service.pressHome()
            }

            is PhoneAction.OpenNotificationShade -> {
                val service = accessibility ?: return logNoService()
                service.openNotifications()
            }

            is PhoneAction.WaitAndObserve -> {
                delay(action.durationMs)
                true
            }

            is PhoneAction.Speak -> {
                voiceEngine.speak(action.text)
                true
            }
        }
    }

    /**
     * Launch an app by package name.
     */
    private fun launchApp(packageName: String): Boolean {
        return try {
            val intent = context.packageManager.getLaunchIntentForPackage(packageName)
            if (intent != null) {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                context.startActivity(intent)
                Log.i(TAG, "Launched app: $packageName")
                true
            } else {
                Log.w(TAG, "No launch intent for package: $packageName")
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to launch app: $packageName", e)
            false
        }
    }

    private fun logNoService(): Boolean {
        Log.w(TAG, "Accessibility service not running — cannot perform action")
        return false
    }
}
