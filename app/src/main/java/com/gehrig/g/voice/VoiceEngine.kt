package com.gehrig.g.voice

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.suspendCancellableCoroutine
import java.util.Locale
import kotlin.coroutines.resume

/**
 * G's voice — handles both listening (speech-to-text) and speaking (text-to-speech).
 * This enables hands-free interaction with G.
 */
class VoiceEngine(private val context: Context) {

    companion object {
        private const val TAG = "VoiceEngine"
    }

    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var speechRecognizer: SpeechRecognizer? = null

    /** Callback when speech is recognized */
    var onSpeechResult: ((String) -> Unit)? = null

    /** Callback for listening state changes */
    var onListeningStateChanged: ((Boolean) -> Unit)? = null

    var isListening = false
        private set

    /**
     * Initialize the voice engine.
     */
    fun initialize() {
        // Initialize Text-to-Speech
        tts = TextToSpeech(context) { status ->
            if (status == TextToSpeech.SUCCESS) {
                tts?.language = Locale.US
                tts?.setSpeechRate(1.1f)  // slightly faster than default for a snappy feel
                tts?.setPitch(0.95f)      // slightly lower pitch for a more assistant-like voice
                ttsReady = true
                Log.i(TAG, "TTS initialized")
            } else {
                Log.e(TAG, "TTS initialization failed with status $status")
            }
        }

        // Initialize Speech Recognizer
        if (SpeechRecognizer.isRecognitionAvailable(context)) {
            speechRecognizer = SpeechRecognizer.createSpeechRecognizer(context)
            speechRecognizer?.setRecognitionListener(createRecognitionListener())
            Log.i(TAG, "Speech recognizer initialized")
        } else {
            Log.w(TAG, "Speech recognition not available on this device")
        }
    }

    /**
     * Speak text aloud.
     */
    fun speak(text: String) {
        if (!ttsReady) {
            Log.w(TAG, "TTS not ready, skipping speech")
            return
        }

        // Stop any current speech
        tts?.stop()

        val params = Bundle().apply {
            putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, 1.0f)
        }

        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, params, "g_speech_${System.currentTimeMillis()}")
        Log.d(TAG, "Speaking: ${text.take(50)}...")
    }

    /**
     * Speak text and wait for completion.
     */
    suspend fun speakAndWait(text: String) = suspendCancellableCoroutine { cont ->
        if (!ttsReady) {
            cont.resume(Unit)
            return@suspendCancellableCoroutine
        }

        tts?.stop()

        val utteranceId = "g_speech_${System.currentTimeMillis()}"

        tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(id: String?) {}

            override fun onDone(id: String?) {
                if (id == utteranceId && cont.isActive) {
                    cont.resume(Unit)
                }
            }

            @Deprecated("Deprecated in Java")
            override fun onError(id: String?) {
                if (cont.isActive) cont.resume(Unit)
            }
        })

        val params = Bundle().apply {
            putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, 1.0f)
        }

        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, params, utteranceId)
    }

    /**
     * Start listening for voice input.
     */
    fun startListening() {
        if (isListening) return

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.US)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
        }

        try {
            speechRecognizer?.startListening(intent)
            isListening = true
            onListeningStateChanged?.invoke(true)
            Log.d(TAG, "Started listening")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start listening", e)
        }
    }

    /**
     * Stop listening.
     */
    fun stopListening() {
        if (!isListening) return
        try {
            speechRecognizer?.stopListening()
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping listener", e)
        }
        isListening = false
        onListeningStateChanged?.invoke(false)
    }

    /**
     * Clean up resources.
     */
    fun shutdown() {
        stopListening()
        speechRecognizer?.destroy()
        speechRecognizer = null
        tts?.stop()
        tts?.shutdown()
        tts = null
    }

    private fun createRecognitionListener() = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {
            Log.d(TAG, "Ready for speech")
        }

        override fun onBeginningOfSpeech() {
            Log.d(TAG, "Speech started")
        }

        override fun onRmsChanged(rmsdB: Float) {
            // Could use this for a voice level indicator in the UI
        }

        override fun onBufferReceived(buffer: ByteArray?) {}

        override fun onEndOfSpeech() {
            isListening = false
            onListeningStateChanged?.invoke(false)
            Log.d(TAG, "Speech ended")
        }

        override fun onError(error: Int) {
            isListening = false
            onListeningStateChanged?.invoke(false)
            val errorMsg = when (error) {
                SpeechRecognizer.ERROR_NO_MATCH -> "No speech detected"
                SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "Speech timeout"
                SpeechRecognizer.ERROR_AUDIO -> "Audio recording error"
                SpeechRecognizer.ERROR_NETWORK -> "Network error"
                else -> "Error code: $error"
            }
            Log.w(TAG, "Recognition error: $errorMsg")
        }

        override fun onResults(results: Bundle?) {
            val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            val text = matches?.firstOrNull()
            if (!text.isNullOrBlank()) {
                Log.i(TAG, "Recognized: $text")
                onSpeechResult?.invoke(text)
            }
        }

        override fun onPartialResults(partialResults: Bundle?) {
            // Could show partial transcription in UI
        }

        override fun onEvent(eventType: Int, params: Bundle?) {}
    }
}
