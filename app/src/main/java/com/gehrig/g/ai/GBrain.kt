package com.gehrig.g.ai

import android.util.Log
import com.gehrig.g.accessibility.GAccessibilityService
import com.gehrig.g.controller.PhoneController
import com.gehrig.g.model.AIAction
import com.gehrig.g.model.AIActionPlan
import com.gehrig.g.model.ClaudeMessage
import com.gehrig.g.model.ConversationMessage
import com.gehrig.g.model.PhoneAction
import com.gehrig.g.model.Role
import com.gehrig.g.model.ScrollDirection
import com.gehrig.g.notification.GNotificationListener
import kotlinx.coroutines.delay
import kotlinx.serialization.json.Json

/**
 * G's brain. Takes user requests, understands what to do, executes multi-step
 * plans on the phone, and responds conversationally.
 *
 * This is the central orchestrator that connects:
 * - User input (voice/text)
 * - Claude API (reasoning)
 * - Accessibility Service (seeing/acting)
 * - Notification Listener (awareness)
 * - Phone Controller (execution)
 */
class GBrain(private val phoneController: PhoneController) {

    companion object {
        private const val TAG = "GBrain"
        private const val MAX_ACTION_STEPS = 15  // safety limit per request
    }

    private val claude = ClaudeClient()
    private val json = Json { ignoreUnknownKeys = true }

    /** Full conversation history */
    private val conversationHistory = mutableListOf<ClaudeMessage>()

    /** Callback for UI updates */
    var onActionUpdate: ((String) -> Unit)? = null

    /**
     * Process a user request end-to-end:
     * 1. Gather context (screen state, notifications)
     * 2. Send to Claude for reasoning
     * 3. Parse and execute action plan
     * 4. Return G's response to the user
     */
    suspend fun processRequest(userMessage: String): ConversationMessage {
        Log.i(TAG, "Processing request: $userMessage")

        // Gather current phone context
        val context = gatherContext()

        // Build the user message with context
        val enrichedMessage = buildString {
            appendLine("USER REQUEST: $userMessage")
            appendLine()
            appendLine(context)
        }

        conversationHistory.add(ClaudeMessage(role = "user", content = enrichedMessage))

        // First pass: get Claude's plan
        val planResult = claude.sendMessage(
            systemPrompt = SYSTEM_PROMPT,
            messages = conversationHistory
        )

        if (planResult.isFailure) {
            val error = planResult.exceptionOrNull()?.message ?: "Unknown error"
            Log.e(TAG, "Claude API failed: $error")
            return ConversationMessage(
                role = Role.ASSISTANT,
                text = "Sorry, I'm having trouble thinking right now. $error"
            )
        }

        val response = planResult.getOrThrow()
        conversationHistory.add(ClaudeMessage(role = "assistant", content = response))

        // Try to parse as action plan
        val actionPlan = tryParseActionPlan(response)

        if (actionPlan != null && actionPlan.actions.isNotEmpty()) {
            // Execute the action plan
            return executeActionPlan(actionPlan, userMessage)
        }

        // No actions needed — just a conversational response
        val cleanResponse = extractResponse(response)
        return ConversationMessage(role = Role.ASSISTANT, text = cleanResponse)
    }

    /**
     * Execute a multi-step action plan on the phone.
     */
    private suspend fun executeActionPlan(
        plan: AIActionPlan,
        originalRequest: String
    ): ConversationMessage {
        Log.i(TAG, "Executing action plan with ${plan.actions.size} steps")

        var stepsExecuted = 0
        for (action in plan.actions) {
            if (stepsExecuted >= MAX_ACTION_STEPS) {
                Log.w(TAG, "Hit max action steps limit")
                break
            }

            onActionUpdate?.invoke(action.description)
            val phoneAction = convertToPhoneAction(action) ?: continue

            Log.d(TAG, "Executing: ${action.description}")
            phoneController.execute(phoneAction)
            stepsExecuted++

            // Brief pause between actions to let the UI settle
            delay(500)
        }

        // After executing actions, observe the result
        if (stepsExecuted > 0) {
            delay(1000)  // let screen settle
            return observeAndRespond(originalRequest)
        }

        return ConversationMessage(
            role = Role.ASSISTANT,
            text = plan.response.ifBlank { "Done." }
        )
    }

    /**
     * After performing actions, look at the screen and give a final answer.
     */
    private suspend fun observeAndRespond(originalRequest: String): ConversationMessage {
        val newContext = gatherContext()

        val observeMessage = buildString {
            appendLine("I've performed the actions. Here's what I see now:")
            appendLine()
            appendLine(newContext)
            appendLine()
            appendLine("Based on what I see, give a natural conversational response to the user's original request: \"$originalRequest\"")
            appendLine("Be concise and direct. Talk like a human assistant, not a robot.")
        }

        conversationHistory.add(ClaudeMessage(role = "user", content = observeMessage))

        val result = claude.sendMessage(
            systemPrompt = SYSTEM_PROMPT,
            messages = conversationHistory
        )

        val responseText = if (result.isSuccess) {
            val resp = result.getOrThrow()
            conversationHistory.add(ClaudeMessage(role = "assistant", content = resp))
            extractResponse(resp)
        } else {
            "I did what you asked but had trouble reading the result."
        }

        return ConversationMessage(role = Role.ASSISTANT, text = responseText)
    }

    /**
     * Gather current phone context for the AI.
     */
    private fun gatherContext(): String = buildString {
        // Screen state
        val accessibility = GAccessibilityService.instance
        if (accessibility != null) {
            appendLine(accessibility.describeScreen())
        } else {
            appendLine("(Accessibility service not running — cannot see screen)")
        }

        appendLine()

        // Notifications
        val notifListener = GNotificationListener.instance
        if (notifListener != null) {
            appendLine(notifListener.describeNotifications())
        } else {
            appendLine("(Notification listener not running)")
        }
    }

    private fun tryParseActionPlan(response: String): AIActionPlan? {
        // Look for JSON block in the response
        val jsonStart = response.indexOf("{")
        val jsonEnd = response.lastIndexOf("}") + 1
        if (jsonStart < 0 || jsonEnd <= jsonStart) return null

        return try {
            val jsonStr = response.substring(jsonStart, jsonEnd)
            json.decodeFromString<AIActionPlan>(jsonStr)
        } catch (e: Exception) {
            Log.d(TAG, "Response is not an action plan (conversational response)")
            null
        }
    }

    private fun convertToPhoneAction(action: AIAction): PhoneAction? {
        return when (action.type.lowercase()) {
            "tap" -> {
                val index = action.target.toIntOrNull()
                if (index != null) PhoneAction.Tap(index, action.description)
                else null
            }
            "tap_coordinates" -> {
                val parts = action.target.split(",")
                if (parts.size == 2) {
                    val x = parts[0].trim().toIntOrNull()
                    val y = parts[1].trim().toIntOrNull()
                    if (x != null && y != null) PhoneAction.TapCoordinates(x, y) else null
                } else null
            }
            "type" -> {
                val index = action.target.toIntOrNull() ?: 0
                PhoneAction.TypeText(index, action.value)
            }
            "scroll_down" -> {
                val index = action.target.toIntOrNull() ?: 0
                PhoneAction.Scroll(index, ScrollDirection.DOWN)
            }
            "scroll_up" -> {
                val index = action.target.toIntOrNull() ?: 0
                PhoneAction.Scroll(index, ScrollDirection.UP)
            }
            "launch_app" -> PhoneAction.LaunchApp(action.target)
            "go_back" -> PhoneAction.GoBack(action.description)
            "go_home" -> PhoneAction.GoHome
            "open_notifications" -> PhoneAction.OpenNotificationShade(action.description)
            "wait" -> {
                val ms = action.value.toLongOrNull() ?: 1000
                PhoneAction.WaitAndObserve(ms, action.description)
            }
            "speak" -> PhoneAction.Speak(action.value)
            else -> {
                Log.w(TAG, "Unknown action type: ${action.type}")
                null
            }
        }
    }

    private fun extractResponse(response: String): String {
        // If the response contains a JSON action plan, extract the "response" field
        val plan = tryParseActionPlan(response)
        if (plan != null && plan.response.isNotBlank()) {
            return plan.response
        }
        // Otherwise return the raw text, stripping any JSON blocks
        return response
            .replace(Regex("```json.*?```", RegexOption.DOT_MATCHES_ALL), "")
            .replace(Regex("\\{[^}]*\"actions\"[^}]*\\}", RegexOption.DOT_MATCHES_ALL), "")
            .trim()
            .ifBlank { response.trim() }
    }

    fun clearHistory() {
        conversationHistory.clear()
    }
}

// ============================================================================
// System prompt — this defines G's personality and capabilities
// ============================================================================

private val SYSTEM_PROMPT = """
You are G, a personal AI phone assistant for Gehrig. You are like Jarvis — capable,
concise, and always helpful. You can see the phone screen, read notifications, and
control the phone by performing actions.

## Your Personality
- You're direct and efficient. No fluff.
- You call Gehrig by name sometimes.
- You're proactive — if you notice something important while doing a task, mention it.
- Keep responses SHORT. One to three sentences max unless asked for detail.

## How You Work
When you need to perform actions on the phone, respond with a JSON action plan:
```json
{
  "thought": "Brief explanation of your plan",
  "actions": [
    {"type": "ACTION_TYPE", "target": "TARGET", "value": "VALUE", "description": "What this does"}
  ],
  "response": "What to tell the user while/after executing"
}
```

## Available Actions
- `launch_app` — target: package name (e.g., "com.google.android.apps.messaging")
- `tap` — target: node index number from the UI tree
- `tap_coordinates` — target: "x,y" screen coordinates
- `type` — target: node index, value: text to type
- `scroll_down` / `scroll_up` — target: node index (or 0 for main scroll)
- `go_back` — press the back button
- `go_home` — go to home screen
- `open_notifications` — pull down notification shade
- `wait` — value: milliseconds to wait
- `speak` — value: text to speak aloud

## Common App Package Names
- Messages: com.google.android.apps.messaging
- Gmail: com.google.android.gm
- Phone: com.google.android.dialer
- Chrome: com.android.chrome
- Settings: com.android.settings
- Camera: com.android.camera2
- Calendar: com.google.android.calendar
- Maps: com.google.android.apps.maps
- YouTube: com.google.android.youtube
- WhatsApp: com.whatsapp
- Instagram: com.instagram.android
- Twitter/X: com.twitter.android

## Rules
1. ALWAYS look at the screen state before deciding actions
2. If you can answer from notifications alone, do that (faster)
3. Only launch apps when you need to see more detail
4. If the screen already shows what you need, just read it and respond
5. Don't perform unnecessary actions
6. If you can't do something, say so honestly
7. For simple questions that don't need phone access, just respond normally (no JSON)
""".trimIndent()
