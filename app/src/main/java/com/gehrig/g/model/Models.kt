package com.gehrig.g.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** A message in the conversation between user and G */
data class ConversationMessage(
    val role: Role,
    val text: String,
    val action: String? = null,   // what G is currently doing, e.g. "Opening Messages..."
    val timestamp: Long = System.currentTimeMillis()
)

enum class Role { USER, ASSISTANT }

/** Represents a UI element G can see on screen */
data class ScreenNode(
    val className: String,
    val text: String?,
    val contentDescription: String?,
    val viewId: String?,
    val isClickable: Boolean,
    val isScrollable: Boolean,
    val isEditable: Boolean,
    val isChecked: Boolean?,
    val bounds: NodeBounds,
    val children: List<ScreenNode>,
    val index: Int
) {
    /** Flatten the tree for easy searching */
    fun flatten(): List<ScreenNode> =
        listOf(this) + children.flatMap { it.flatten() }

    /** Human-readable description for the AI */
    fun describe(depth: Int = 0): String {
        val indent = "  ".repeat(depth)
        val parts = mutableListOf<String>()
        parts.add("[$index]")
        parts.add(className.substringAfterLast('.'))
        text?.let { if (it.isNotBlank()) parts.add("text=\"$it\"") }
        contentDescription?.let { if (it.isNotBlank()) parts.add("desc=\"$it\"") }
        viewId?.let { parts.add("id=$it") }
        if (isClickable) parts.add("[clickable]")
        if (isScrollable) parts.add("[scrollable]")
        if (isEditable) parts.add("[editable]")
        isChecked?.let { parts.add(if (it) "[checked]" else "[unchecked]") }

        val line = "$indent${parts.joinToString(" ")}"
        val childLines = children.mapNotNull { child ->
            val desc = child.describe(depth + 1)
            if (desc.isNotBlank()) desc else null
        }
        return (listOf(line) + childLines).joinToString("\n")
    }
}

data class NodeBounds(
    val left: Int,
    val top: Int,
    val right: Int,
    val bottom: Int
) {
    val centerX: Int get() = (left + right) / 2
    val centerY: Int get() = (top + bottom) / 2
}

/** An intercepted notification */
data class CapturedNotification(
    val packageName: String,
    val appName: String,
    val title: String?,
    val text: String?,
    val timestamp: Long,
    val key: String
)

/** Actions G can perform on the phone */
sealed class PhoneAction {
    data class Tap(val nodeIndex: Int, val description: String) : PhoneAction()
    data class TapCoordinates(val x: Int, val y: Int) : PhoneAction()
    data class TypeText(val nodeIndex: Int, val text: String) : PhoneAction()
    data class Scroll(val nodeIndex: Int, val direction: ScrollDirection) : PhoneAction()
    data class LaunchApp(val packageName: String) : PhoneAction()
    data class GoBack(val reason: String) : PhoneAction()
    data object GoHome : PhoneAction()
    data class OpenNotificationShade(val reason: String) : PhoneAction()
    data class WaitAndObserve(val durationMs: Long, val reason: String) : PhoneAction()
    data class Speak(val text: String) : PhoneAction()
}

enum class ScrollDirection { UP, DOWN, LEFT, RIGHT }

// --- Claude API models ---

@Serializable
data class ClaudeRequest(
    val model: String = "claude-sonnet-4-20250514",
    val max_tokens: Int = 4096,
    val system: String,
    val messages: List<ClaudeMessage>
)

@Serializable
data class ClaudeMessage(
    val role: String,
    val content: String
)

@Serializable
data class ClaudeResponse(
    val id: String = "",
    val type: String = "",
    val content: List<ClaudeContentBlock> = emptyList(),
    val stop_reason: String? = null
)

@Serializable
data class ClaudeContentBlock(
    val type: String,
    val text: String = ""
)

/** Parsed action from Claude's response */
@Serializable
data class AIActionPlan(
    val thought: String = "",
    val actions: List<AIAction> = emptyList(),
    val response: String = ""
)

@Serializable
data class AIAction(
    val type: String,
    val target: String = "",
    val value: String = "",
    val description: String = ""
)
