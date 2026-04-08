package com.gehrig.g.ai

import android.util.Log
import com.gehrig.g.GApplication
import com.gehrig.g.model.ClaudeContentBlock
import com.gehrig.g.model.ClaudeMessage
import com.gehrig.g.model.ClaudeRequest
import com.gehrig.g.model.ClaudeResponse
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit

/**
 * Client for the Claude API. Handles sending messages and receiving responses.
 */
class ClaudeClient {

    companion object {
        private const val TAG = "ClaudeClient"
        private const val API_URL = "https://api.anthropic.com/v1/messages"
        private const val API_VERSION = "2023-06-01"
    }

    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .build()

    /**
     * Send a message to Claude and get a response.
     */
    suspend fun sendMessage(
        systemPrompt: String,
        messages: List<ClaudeMessage>
    ): Result<String> = withContext(Dispatchers.IO) {
        val apiKey = GApplication.instance.claudeApiKey
        if (apiKey.isBlank()) {
            return@withContext Result.failure(IllegalStateException("No API key configured. Set it in Settings."))
        }

        val request = ClaudeRequest(
            system = systemPrompt,
            messages = messages
        )

        val requestBody = json.encodeToString(request)
        Log.d(TAG, "Sending request to Claude (${messages.size} messages)")

        val httpRequest = Request.Builder()
            .url(API_URL)
            .addHeader("x-api-key", apiKey)
            .addHeader("anthropic-version", API_VERSION)
            .addHeader("content-type", "application/json")
            .post(requestBody.toRequestBody("application/json".toMediaType()))
            .build()

        try {
            val response = httpClient.newCall(httpRequest).execute()
            val body = response.body?.string() ?: ""

            if (!response.isSuccessful) {
                Log.e(TAG, "Claude API error ${response.code}: $body")
                return@withContext Result.failure(
                    RuntimeException("Claude API error ${response.code}: ${body.take(200)}")
                )
            }

            val claudeResponse = json.decodeFromString<ClaudeResponse>(body)
            val text = claudeResponse.content
                .filter { it.type == "text" }
                .joinToString("") { it.text }

            Log.d(TAG, "Got response from Claude (${text.length} chars)")
            Result.success(text)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to call Claude API", e)
            Result.failure(e)
        }
    }
}
