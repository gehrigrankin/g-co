import Foundation

/// G's brain. Orchestrates Claude API calls with tool use to answer questions
/// and perform actions. This is the central intelligence of the app.
///
/// How it works:
/// 1. User asks something → brain sends to Claude with available tools
/// 2. Claude reasons and may call tools (read_messages, search_contacts, etc.)
/// 3. Brain executes tools locally, feeds results back to Claude
/// 4. Claude synthesizes a final natural language response
/// 5. Loop repeats if Claude needs more tool calls
actor GBrain {
    private let claude = ClaudeClient()
    private let toolExecutor = ToolExecutor()
    private var conversationHistory: [ClaudeMessage] = []

    private let maxToolRounds = 8 // safety limit

    /// Process a user request end-to-end, returning G's response.
    func processRequest(_ userMessage: String) async throws -> String {
        // Add user message to history
        conversationHistory.append(ClaudeMessage(role: "user", text: userMessage))

        // Agent loop: Claude may need multiple rounds of tool calls
        var rounds = 0
        while rounds < maxToolRounds {
            rounds += 1

            let response = try await claude.send(
                system: Self.systemPrompt,
                messages: conversationHistory,
                tools: Self.tools
            )

            // Separate text blocks from tool-use blocks
            var textParts: [String] = []
            var toolCalls: [(id: String, name: String, input: [String: Any])] = []

            for block in response.content {
                if block.type == "text", let text = block.text {
                    textParts.append(text)
                } else if block.type == "tool_use",
                          let id = block.id,
                          let name = block.name {
                    let input = block.input?.mapValues { $0.value } ?? [:]
                    toolCalls.append((id: id, name: name, input: input))
                }
            }

            // If no tool calls, we're done — return the text response
            if toolCalls.isEmpty {
                let finalText = textParts.joined(separator: "\n")
                conversationHistory.append(ClaudeMessage(role: "assistant", text: finalText))
                return finalText
            }

            // Build assistant message with tool_use blocks for history
            var assistantBlocks: [ClaudeContentBlock] = []
            for part in textParts {
                assistantBlocks.append(ClaudeContentBlock(type: "text", text: part))
            }
            // We need to add tool_use blocks to the conversation too
            // For simplicity, add the text response if any
            let assistantText = textParts.joined(separator: "\n")
            if !assistantText.isEmpty {
                conversationHistory.append(ClaudeMessage(role: "assistant", text: assistantText))
            }

            // Execute each tool call and collect results
            var toolResults: [String] = []
            for call in toolCalls {
                let result = await toolExecutor.execute(
                    tool: call.name,
                    input: call.input
                )
                toolResults.append("[\(call.name)] \(result)")
            }

            // Feed tool results back to Claude
            let resultsText = toolResults.joined(separator: "\n\n")
            conversationHistory.append(ClaudeMessage(
                role: "user",
                text: "Tool results:\n\(resultsText)\n\nBased on these results, give me a concise response."
            ))

            // If Claude said stop, we're done
            if response.stop_reason == "end_turn" && !toolCalls.isEmpty {
                // Had tool calls but also ended — continue for one more round to get synthesis
                continue
            }
        }

        return "I tried multiple approaches but couldn't complete that request. Could you try rephrasing?"
    }

    func clearHistory() {
        conversationHistory.removeAll()
    }
}

// MARK: - Tool Definitions

extension GBrain {
    /// All tools G can use — these get sent to Claude so it knows what's available.
    static let tools: [ClaudeTool] = [
        // Messages
        ClaudeTool(
            name: "read_messages",
            description: "Read recent text messages (SMS/iMessage). Returns the most recent messages, optionally filtered by contact name.",
            input_schema: ToolSchema(
                properties: [
                    "contact": ToolProperty(type: "string", description: "Filter by contact name (optional)"),
                    "limit": ToolProperty(type: "integer", description: "Max messages to return (default 20)")
                ],
                required: []
            )
        ),

        // Contacts
        ClaudeTool(
            name: "search_contacts",
            description: "Search the user's contacts by name, phone number, or email.",
            input_schema: ToolSchema(
                properties: [
                    "query": ToolProperty(type: "string", description: "Search query (name, number, or email)")
                ],
                required: ["query"]
            )
        ),

        // Calendar
        ClaudeTool(
            name: "read_calendar",
            description: "Read upcoming calendar events. Can filter by date range.",
            input_schema: ToolSchema(
                properties: [
                    "days_ahead": ToolProperty(type: "integer", description: "How many days ahead to look (default 7)"),
                    "query": ToolProperty(type: "string", description: "Filter events by title (optional)")
                ],
                required: []
            )
        ),
        ClaudeTool(
            name: "create_calendar_event",
            description: "Create a new calendar event.",
            input_schema: ToolSchema(
                properties: [
                    "title": ToolProperty(type: "string", description: "Event title"),
                    "date": ToolProperty(type: "string", description: "Date in YYYY-MM-DD format"),
                    "time": ToolProperty(type: "string", description: "Time in HH:MM format (24h)"),
                    "duration_minutes": ToolProperty(type: "integer", description: "Duration in minutes (default 60)")
                ],
                required: ["title", "date"]
            )
        ),

        // Reminders
        ClaudeTool(
            name: "read_reminders",
            description: "Read the user's reminders/tasks, optionally filtered by list name.",
            input_schema: ToolSchema(
                properties: [
                    "list": ToolProperty(type: "string", description: "Reminder list name (optional)"),
                    "include_completed": ToolProperty(type: "boolean", description: "Include completed reminders (default false)")
                ],
                required: []
            )
        ),
        ClaudeTool(
            name: "create_reminder",
            description: "Create a new reminder.",
            input_schema: ToolSchema(
                properties: [
                    "title": ToolProperty(type: "string", description: "Reminder title"),
                    "due_date": ToolProperty(type: "string", description: "Due date in YYYY-MM-DD format (optional)"),
                    "notes": ToolProperty(type: "string", description: "Additional notes (optional)")
                ],
                required: ["title"]
            )
        ),

        // Email (via IMAP when configured)
        ClaudeTool(
            name: "read_emails",
            description: "Read recent emails from the user's inbox. Returns subject, sender, and preview.",
            input_schema: ToolSchema(
                properties: [
                    "folder": ToolProperty(type: "string", description: "Email folder (default INBOX)"),
                    "limit": ToolProperty(type: "integer", description: "Max emails to return (default 10)"),
                    "unread_only": ToolProperty(type: "boolean", description: "Only show unread emails (default false)")
                ],
                required: []
            )
        ),

        // App launching
        ClaudeTool(
            name: "open_app",
            description: "Open an app on the user's phone via URL scheme.",
            input_schema: ToolSchema(
                properties: [
                    "app": ToolProperty(
                        type: "string",
                        description: "App to open",
                        options: ["messages", "mail", "safari", "maps", "calendar", "photos", "settings", "phone", "notes", "reminders", "music", "weather"]
                    )
                ],
                required: ["app"]
            )
        ),

        // Web search
        ClaudeTool(
            name: "web_search",
            description: "Open a web search in Safari for the user.",
            input_schema: ToolSchema(
                properties: [
                    "query": ToolProperty(type: "string", description: "Search query")
                ],
                required: ["query"]
            )
        ),

        // Device info
        ClaudeTool(
            name: "get_device_info",
            description: "Get current device info: battery level, time, storage, etc.",
            input_schema: ToolSchema(
                properties: [:],
                required: []
            )
        ),
    ]
}

// MARK: - System Prompt

extension GBrain {
    static let systemPrompt = """
    You are G, a personal AI phone assistant for Gehrig. You are like Jarvis — capable, \
    concise, and always helpful. You have direct access to Gehrig's phone data through tools.

    ## Your Personality
    - You're direct and efficient. No fluff.
    - You call Gehrig by name sometimes.
    - You're proactive — if you notice something important while doing a task, mention it.
    - Keep responses SHORT. One to three sentences max unless asked for detail.
    - Be conversational and natural, not robotic.

    ## How You Work
    You have tools to access phone data directly — messages, contacts, calendar, reminders, \
    email. When the user asks about something, USE the appropriate tool to get real data. \
    Don't make up information.

    ## Rules
    1. ALWAYS use tools when the question requires phone data. Don't guess.
    2. If you can answer from general knowledge (no phone data needed), just respond directly.
    3. Be concise in your final response — the user wants answers, not a data dump.
    4. If a tool fails or data isn't available, say so honestly.
    5. If the user asks you to do something you can't (like control another app), explain what \
       you CAN do instead.
    6. For messages: prioritize recent and important ones. Skip spam/promos unless asked.
    7. For calendar: always mention the day of the week, not just the date.
    """
}
