# G — AI Phone Assistant for iPhone

G is a Jarvis-like AI assistant for your iPhone. Ask G anything — it'll check your messages, calendar, contacts, reminders, and more, then give you a natural conversational answer.

## What G Can Do

- **Messages** — read incoming messages (via Shortcuts automation) and compose replies
- **Calendar** — read upcoming events, create new ones
- **Contacts** — search by name, phone, or email
- **Reminders** — read tasks, create new reminders
- **Email** — read email summaries (via Shortcuts forwarding)
- **Voice** — talk to G hands-free with speech recognition + spoken responses
- **Siri Shortcuts** — "Hey Siri, ask G if I have anything today"
- **Open Apps** — launch Messages, Mail, Safari, Maps, and more via URL schemes
- **AI Reasoning** — powered by Claude for natural language understanding

## Example

> **You:** "G, do I have anything on my calendar today?"
>
> **G:** *checks EventKit* "You've got two things — a team standup at 10 AM and dinner with Sarah at 7. Nothing else."

> **You:** "Remind me to pick up groceries tomorrow"
>
> **G:** *creates reminder* "Done — I set a reminder for tomorrow."

## Architecture

```
┌──────────────────────────────────────┐
│               User                    │
│         (Voice / Text Input)          │
└─────────────┬────────────────────────┘
              │
       ┌──────▼───────┐
       │  GAssistant   │  ← Main coordinator
       │ (SwiftUI VM)  │
       └──┬────┬────┬──┘
          │    │    │
   ┌──────▼┐ ┌▼───┐ ┌▼──────────┐
   │ GBrain │ │Voice│ │  Tool     │
   │(Claude │ │Engine│ │ Executor │
   │  API)  │ │(STT/ │ │          │
   └────────┘ │ TTS) │ └────┬─────┘
              └──────┘      │
                    ┌───────▼───────┐
                    │ Data Providers │
                    ├───────────────┤
                    │ Contacts      │ ← CNContactStore
                    │ Calendar      │ ← EventKit
                    │ Reminders     │ ← EventKit
                    │ Messages      │ ← Shortcuts forwarding
                    │ Email         │ ← Shortcuts forwarding
                    └───────────────┘
```

### Key Design Decision: Tool Use

G uses Claude's **tool-use API** instead of hardcoded workflows. When you ask a question:

1. Your question goes to Claude with a list of available tools
2. Claude decides which tools to call (e.g., `read_calendar`, `search_contacts`)
3. G executes tools locally using iOS frameworks
4. Results go back to Claude for synthesis
5. Claude gives you a natural language answer

This means G can handle complex multi-step requests without hardcoding every possible workflow.

## Setup

1. Open the project in Xcode (create a new iOS App project, drag the `G/` folder in)
2. Set deployment target to iOS 17.0+
3. Add required capabilities in Xcode:
   - Siri
   - App Groups (optional, for Shortcuts data sharing)
4. Build and run on your iPhone
5. On first launch, enter your Claude API key (from console.anthropic.com)
6. Grant permissions when prompted (Contacts, Calendar, Reminders, Microphone, Speech)

### Setting Up Message Forwarding

Since iOS doesn't let apps read Messages directly:

1. Open the **Shortcuts** app
2. Go to **Automation** → **New Automation**
3. Trigger: **Message** → "When I receive a message"
4. Action: **Forward Message to G** (this appears after installing G)
5. Done — G will now see your incoming messages

## Tech Stack

- **Swift 5.9** + **SwiftUI** — native iOS, no cross-platform overhead
- **Claude API** (tool use) — AI reasoning via direct HTTP calls with URLSession
- **Contacts framework** — full contact search
- **EventKit** — calendar and reminders read/write
- **Speech framework** — on-device speech recognition
- **AVSpeechSynthesizer** — text-to-speech
- **AppIntents** — Siri Shortcuts integration

## Project Structure

```
G/
├── GApp.swift                    # App entry point
├── Info.plist                    # Permissions + config
├── AI/
│   ├── ClaudeClient.swift        # Claude API HTTP client
│   ├── GBrain.swift              # AI reasoning engine + tool definitions
│   ├── GAssistant.swift          # Main coordinator (owns brain + voice)
│   └── ToolExecutor.swift        # Dispatches tool calls to data providers
├── Data/
│   ├── ContactProvider.swift     # Contacts framework integration
│   ├── CalendarProvider.swift    # EventKit calendar read/write
│   ├── ReminderProvider.swift    # EventKit reminders read/write
│   ├── MessageProvider.swift     # Message store (Shortcuts-fed)
│   └── EmailProvider.swift       # Email store (Shortcuts-fed)
├── Voice/
│   └── VoiceEngine.swift         # Speech recognition + TTS
├── Shortcuts/
│   └── GShortcuts.swift          # Siri Shortcuts / App Intents
├── UI/
│   ├── ContentView.swift         # Root navigation
│   ├── ConversationView.swift    # Chat interface
│   ├── SettingsView.swift        # API key + permissions
│   ├── OnboardingView.swift      # First-launch setup
│   └── Components/
│       └── Colors.swift          # Color palette
├── Models/
│   └── Models.swift              # Data types
└── Assets.xcassets/              # App icon + colors
```

## iOS Limitations (Honest)

Apple's sandbox means G can't do everything an Android assistant could:

| Capability | Status | How |
|-----------|--------|-----|
| Read messages | Via Shortcuts | User sets up automation to forward to G |
| Send messages | Partial | Opens compose sheet (user taps send) |
| Read contacts | Full | CNContactStore API |
| Read calendar | Full | EventKit API |
| Create events | Full | EventKit API |
| Read reminders | Full | EventKit API |
| Create reminders | Full | EventKit API |
| Read emails | Via Shortcuts | User forwards summaries to G |
| Open apps | URL schemes | Can open most built-in apps |
| Voice input | Full | On-device Speech framework |
| Voice output | Full | AVSpeechSynthesizer |
| Control other apps | Not possible | Apple doesn't allow this |
| Read notifications | Not possible | Apple doesn't allow this |
| Always-on listening | Not possible | iOS background limits |
