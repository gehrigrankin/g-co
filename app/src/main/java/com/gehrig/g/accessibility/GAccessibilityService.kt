package com.gehrig.g.accessibility

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.graphics.Rect
import android.os.Bundle
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import com.gehrig.g.model.NodeBounds
import com.gehrig.g.model.ScreenNode
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

/**
 * G's eyes and hands. This service can:
 * - Read the entire screen content (UI tree)
 * - Tap any element
 * - Type text into fields
 * - Scroll views
 * - Perform gestures (swipe, etc.)
 * - Navigate (back, home, recents)
 */
class GAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "GAccessibility"

        /** Singleton reference — set when the service connects */
        var instance: GAccessibilityService? = null
            private set

        val isRunning: Boolean get() = instance != null
    }

    // Tracks the current foreground app
    var currentPackage: String = ""
        private set
    var currentActivity: String = ""
        private set

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.i(TAG, "G Accessibility Service connected — G can now see and control the phone")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        event ?: return

        // Track which app/activity is in the foreground
        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> {
                event.packageName?.toString()?.let { currentPackage = it }
                event.className?.toString()?.let { currentActivity = it }
            }
        }
    }

    override fun onInterrupt() {
        Log.w(TAG, "G Accessibility Service interrupted")
    }

    override fun onDestroy() {
        instance = null
        Log.i(TAG, "G Accessibility Service destroyed")
        super.onDestroy()
    }

    // ========================================================================
    // SCREEN READING — G's eyes
    // ========================================================================

    /**
     * Capture the entire screen's UI tree as a structured [ScreenNode].
     * This is how G "sees" what's on screen.
     */
    fun captureScreen(): ScreenNode? {
        val root = rootInActiveWindow ?: return null
        return try {
            parseNode(root, 0)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to capture screen", e)
            null
        } finally {
            root.recycle()
        }
    }

    /**
     * Get a text description of the current screen for the AI.
     * This is what gets sent to Claude so it can understand the screen.
     */
    fun describeScreen(): String {
        val screen = captureScreen()
        return buildString {
            appendLine("=== SCREEN STATE ===")
            appendLine("Current app: $currentPackage")
            appendLine("Current activity: $currentActivity")
            appendLine()
            if (screen != null) {
                appendLine("UI Tree:")
                appendLine(screen.describe())
            } else {
                appendLine("(Unable to read screen)")
            }
        }
    }

    /**
     * Find all nodes matching a text query (case-insensitive).
     */
    fun findNodesByText(query: String): List<ScreenNode> {
        val screen = captureScreen() ?: return emptyList()
        return screen.flatten().filter { node ->
            node.text?.contains(query, ignoreCase = true) == true ||
            node.contentDescription?.contains(query, ignoreCase = true) == true
        }
    }

    private var nodeCounter = 0

    private fun parseNode(node: AccessibilityNodeInfo, depth: Int): ScreenNode {
        val bounds = Rect()
        node.getBoundsInScreen(bounds)

        val children = mutableListOf<ScreenNode>()
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            try {
                children.add(parseNode(child, depth + 1))
            } finally {
                child.recycle()
            }
        }

        return ScreenNode(
            className = node.className?.toString() ?: "Unknown",
            text = node.text?.toString(),
            contentDescription = node.contentDescription?.toString(),
            viewId = node.viewIdResourceName,
            isClickable = node.isClickable,
            isScrollable = node.isScrollable,
            isEditable = node.isEditable,
            isChecked = if (node.isCheckable) node.isChecked else null,
            bounds = NodeBounds(bounds.left, bounds.top, bounds.right, bounds.bottom),
            children = children,
            index = nodeCounter++
        )
    }

    // ========================================================================
    // ACTIONS — G's hands
    // ========================================================================

    /**
     * Tap on a specific node by its index in the UI tree.
     */
    fun tapNode(nodeIndex: Int): Boolean {
        val screen = captureScreen() ?: return false
        val target = screen.flatten().find { it.index == nodeIndex } ?: return false
        return tapAtCoordinates(target.bounds.centerX, target.bounds.centerY)
    }

    /**
     * Tap at specific screen coordinates.
     */
    fun tapAtCoordinates(x: Int, y: Int): Boolean {
        val path = Path().apply { moveTo(x.toFloat(), y.toFloat()) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 100))
            .build()

        return dispatchGesture(gesture, null, null)
    }

    /**
     * Type text into a focused or specified editable field.
     */
    fun typeText(nodeIndex: Int, text: String): Boolean {
        val root = rootInActiveWindow ?: return false
        return try {
            val target = findEditableNode(root, nodeIndex)
            if (target != null) {
                // Focus the node
                target.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
                // Clear existing text
                val clearArgs = Bundle().apply {
                    putCharSequence(
                        AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                        text
                    )
                }
                target.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, clearArgs)
                true
            } else {
                Log.w(TAG, "Could not find editable node at index $nodeIndex")
                false
            }
        } finally {
            root.recycle()
        }
    }

    private fun findEditableNode(node: AccessibilityNodeInfo, targetIndex: Int): AccessibilityNodeInfo? {
        // Simple BFS to find the node - in practice we track index during traversal
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(node)
        var index = 0

        while (queue.isNotEmpty()) {
            val current = queue.removeFirst()
            if (index == targetIndex && current.isEditable) {
                return current
            }
            index++
            for (i in 0 until current.childCount) {
                current.getChild(i)?.let { queue.add(it) }
            }
        }
        return null
    }

    /**
     * Scroll a node in a direction.
     */
    fun scroll(nodeIndex: Int, forward: Boolean): Boolean {
        val root = rootInActiveWindow ?: return false
        return try {
            val target = findScrollableNode(root)
            if (target != null) {
                val action = if (forward)
                    AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
                else
                    AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
                target.performAction(action)
            } else {
                // Fall back to gesture-based scrolling
                gestureScroll(forward)
            }
        } finally {
            root.recycle()
        }
    }

    private fun findScrollableNode(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        if (node.isScrollable) return node
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val result = findScrollableNode(child)
            if (result != null) return result
            child.recycle()
        }
        return null
    }

    /**
     * Perform a swipe gesture for scrolling.
     */
    private fun gestureScroll(forward: Boolean): Boolean {
        val displayMetrics = resources.displayMetrics
        val centerX = displayMetrics.widthPixels / 2f
        val startY: Float
        val endY: Float

        if (forward) {
            startY = displayMetrics.heightPixels * 0.7f
            endY = displayMetrics.heightPixels * 0.3f
        } else {
            startY = displayMetrics.heightPixels * 0.3f
            endY = displayMetrics.heightPixels * 0.7f
        }

        val path = Path().apply {
            moveTo(centerX, startY)
            lineTo(centerX, endY)
        }

        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 300))
            .build()

        return dispatchGesture(gesture, null, null)
    }

    /**
     * Swipe in a direction (for things like dismissing, navigating).
     */
    fun swipe(startX: Int, startY: Int, endX: Int, endY: Int, durationMs: Long = 300): Boolean {
        val path = Path().apply {
            moveTo(startX.toFloat(), startY.toFloat())
            lineTo(endX.toFloat(), endY.toFloat())
        }

        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, durationMs))
            .build()

        return dispatchGesture(gesture, null, null)
    }

    // ========================================================================
    // NAVIGATION — G's movement
    // ========================================================================

    fun pressBack(): Boolean = performGlobalAction(GLOBAL_ACTION_BACK)

    fun pressHome(): Boolean = performGlobalAction(GLOBAL_ACTION_HOME)

    fun openRecents(): Boolean = performGlobalAction(GLOBAL_ACTION_RECENTS)

    fun openNotifications(): Boolean = performGlobalAction(GLOBAL_ACTION_NOTIFICATIONS)

    fun openQuickSettings(): Boolean = performGlobalAction(GLOBAL_ACTION_QUICK_SETTINGS)

    fun lockScreen(): Boolean = performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)

    fun takeScreenshot(): Boolean = performGlobalAction(GLOBAL_ACTION_TAKE_SCREENSHOT)
}
