# G — AI Phone Assistant

G is a Jarvis-like AI assistant that can see, understand, and control your Android phone. Ask G anything and it will navigate your phone, read your messages, check your emails, and perform actions on your behalf.

## What G Can Do

- **See your screen** — reads the full UI tree of any app via Accessibility Service
- **Control your phone** — tap, swipe, type, scroll, launch apps, navigate
- **Read notifications** — intercepts all notifications across all apps in real-time
- **Understand context** — powered by Claude AI for natural language understanding
- **Talk to you** — voice input and text-to-speech responses
- **Stay alive** — runs as a foreground service, always ready

## Example

> **You:** "G, do I have any unread messages I need to worry about?"
>
> **G:** *opens Messages, scans conversations* "No, Gehrig, nothing urgent. Just a promo text from your carrier."

## Architecture

```
┌─────────────────────────────────────────────┐
│                   User                       │
│            (Voice / Text Input)              │
└──────────────────┬──────────────────────────┘
                   │
        ┌──────────▼──────────┐
        │   GAssistantService  │  ← Foreground service (always alive)
        │   (Orchestrator)     │
        └──┬───────┬───────┬──┘
           │       │       │
    ┌──────▼──┐ ┌──▼───┐ ┌▼──────────┐
    │  GBrain  │ │Voice │ │  Phone    │
    │ (Claude  │ │Engine│ │ Controller│
    │   API)   │ │(STT/ │ │ (Execute) │
    └──────────┘ │ TTS) │ └─────┬─────┘
                 └──────┘       │
                         ┌──────▼──────────┐
                         │  Accessibility   │
                         │  Service         │
                         │ (See + Control)  │
                         └──────┬──────────┘
                                │
                         ┌──────▼──────────┐
                         │  Notification    │
                         │  Listener        │
                         │ (All notifs)     │
                         └─────────────────┘
```

## Setup

1. Clone and open in Android Studio
2. Add your Claude API key in `local.properties`:
   ```
   CLAUDE_API_KEY=sk-ant-...
   ```
   Or set it in the app's Settings screen after install.
3. Build and install on your Android device
4. Grant permissions:
   - **Accessibility Service** — Settings → Accessibility → G
   - **Notification Access** — Settings → Notification Access → G
   - **Microphone** — for voice input
   - **SMS, Contacts, Calendar** — for direct data access

## Tech Stack

- **Kotlin** — Android native for deepest OS integration
- **Claude API** — AI reasoning and natural language understanding
- **Android Accessibility Service** — screen reading and UI automation
- **NotificationListenerService** — notification interception
- **SpeechRecognizer + TextToSpeech** — voice interface
- **OkHttp** — networking
- **Kotlinx Serialization** — JSON handling

## Project Structure

```
app/src/main/java/com/gehrig/g/
├── GApplication.kt              # App-level init, prefs, notification channels
├── accessibility/
│   └── GAccessibilityService.kt # Screen reading + UI control
├── ai/
│   ├── ClaudeClient.kt          # Claude API HTTP client
│   └── GBrain.kt                # AI orchestrator — plans and executes
├── controller/
│   └── PhoneController.kt       # Executes phone actions
├── model/
│   └── Models.kt                # Data models
├── notification/
│   └── GNotificationListener.kt # Notification interception
├── service/
│   └── GAssistantService.kt     # Foreground service (keeps G alive)
├── ui/
│   ├── ConversationAdapter.kt   # Chat message list
│   ├── MainActivity.kt          # Main conversation UI
│   └── SettingsActivity.kt      # API key + permissions config
└── voice/
    └── VoiceEngine.kt           # Speech-to-text + text-to-speech
```
