import Foundation

/// G's brain. This is the central intelligence — not a phone tool, but a personal
/// assistant that knows Gehrig, learns over time, and happens to have phone access.
///
/// Every conversation:
/// 1. G loads its memory of Gehrig into context
/// 2. Processes the request with Claude (using tools if needed)
/// 3. Extracts any new information learned about Gehrig
/// 4. Stores it in persistent memory for future conversations
actor GBrain {
    private let claude = ClaudeClient()
    private let toolExecutor = ToolExecutor()
    private var conversationHistory: [ClaudeMessage] = []
    private var turnCount = 0

    private let maxToolRounds = 8

    // MARK: - Process Request

    /// Process a user request. G uses its memory, tools, and reasoning.
    func processRequest(_ userMessage: String) async throws -> String {
        conversationHistory.append(ClaudeMessage(role: "user", text: userMessage))
        turnCount += 1

        // Build system prompt with current memory
        let systemPrompt = await buildSystemPrompt()

        // Agent loop
        var rounds = 0
        while rounds < maxToolRounds {
            rounds += 1

            let response = try await claude.send(
                system: systemPrompt,
                messages: conversationHistory,
                tools: Self.tools
            )

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

            // Handle memory extraction tool
            for call in toolCalls where call.name == "store_memory" {
                await handleMemoryStorage(call.input)
            }

            // Filter out memory tool calls from execution
            let actionCalls = toolCalls.filter { $0.name != "store_memory" }

            if actionCalls.isEmpty && toolCalls.count == toolCalls.filter({ $0.name == "store_memory" }).count && !textParts.isEmpty {
                // Only memory stores + text response = we're done
                let finalText = textParts.joined(separator: "\n")
                conversationHistory.append(ClaudeMessage(role: "assistant", text: finalText))
                await postConversationLearning(userMessage: userMessage, response: finalText)
                return finalText
            }

            if actionCalls.isEmpty {
                let finalText = textParts.joined(separator: "\n")
                conversationHistory.append(ClaudeMessage(role: "assistant", text: finalText))
                await postConversationLearning(userMessage: userMessage, response: finalText)
                return finalText
            }

            let assistantText = textParts.joined(separator: "\n")
            if !assistantText.isEmpty {
                conversationHistory.append(ClaudeMessage(role: "assistant", text: assistantText))
            }

            // Execute tool calls
            var toolResults: [String] = []
            for call in actionCalls {
                let result = await toolExecutor.execute(tool: call.name, input: call.input)
                toolResults.append("[\(call.name)] \(result)")
            }

            let resultsText = toolResults.joined(separator: "\n\n")
            conversationHistory.append(ClaudeMessage(
                role: "user",
                text: "Tool results:\n\(resultsText)\n\nRespond concisely."
            ))

            if response.stop_reason == "end_turn" && !actionCalls.isEmpty {
                continue
            }
        }

        return "I tried a few things but couldn't get there. What if you try asking differently?"
    }

    // MARK: - Memory Integration

    /// Build the system prompt with G's current memory and recent conversation context.
    private func buildSystemPrompt() async -> String {
        let memory = await MainActor.run { GMemory.shared }
        let memoryContext = await MainActor.run { memory.getContextForAI() }
        let recentConvoContext = ConversationStore.shared.getRecentContext(maxMessages: 15)

        var prompt = """
        \(Self.coreIdentity)

        \(memoryContext)
        """

        if !recentConvoContext.isEmpty {
            prompt += "\n\n\(recentConvoContext)"
        }

        prompt += """

        \(Self.memoryInstructions)

        \(Self.toolInstructions)
        """

        return prompt
    }

    /// Handle the store_memory tool call from Claude.
    private func handleMemoryStorage(_ input: [String: Any]) async {
        guard let content = input["content"] as? String,
              let categoryStr = input["category"] as? String,
              let category = GMemory.MemoryCategory(rawValue: categoryStr) else {
            return
        }
        let confidence = input["confidence"] as? Double ?? 0.8

        await MainActor.run {
            GMemory.shared.remember(content, category: category, confidence: confidence)
        }
    }

    /// After each conversation turn, extract and store any new learnings.
    /// This runs as a background pass so it doesn't slow down the response.
    private func postConversationLearning(userMessage: String, response: String) async {
        // Every 3 turns, ask Claude to extract memories from the conversation
        guard turnCount % 3 == 0 else { return }

        let extractionPrompt = """
        Review this recent exchange and extract any new facts about the user that \
        should be remembered for future conversations. Only extract genuinely new or \
        updated information — not things already known.

        User said: "\(userMessage)"
        You responded: "\(response)"

        If there's nothing new to learn, just respond with "nothing new".
        Otherwise, list what you learned in this format (one per line):
        category|content|confidence

        Valid categories: fact, preference, relationship, routine, interest, work, \
        health, location, personality, goal, dislike, context

        Confidence: 0.5 (inferred), 0.8 (likely), 1.0 (explicitly stated)
        """

        let messages = [ClaudeMessage(role: "user", text: extractionPrompt)]

        if let result = try? await claude.send(
            system: "You extract structured information about a user from conversations. Be selective — only extract meaningful, specific facts.",
            messages: messages,
            tools: nil
        ) {
            let text = result.content.compactMap { $0.text }.joined()
            if text.lowercased().contains("nothing new") { return }

            let lines = text.split(separator: "\n")
            var extractions: [MemoryExtraction] = []

            for line in lines {
                let parts = line.split(separator: "|", maxSplits: 2).map(String.init)
                guard parts.count >= 2 else { continue }
                let categoryStr = parts[0].trimmingCharacters(in: .whitespaces)
                let content = parts[1].trimmingCharacters(in: .whitespaces)
                let confidence = parts.count > 2 ? Double(parts[2].trimmingCharacters(in: .whitespaces)) ?? 0.8 : 0.8

                if let category = GMemory.MemoryCategory(rawValue: categoryStr) {
                    extractions.append(MemoryExtraction(
                        content: content,
                        category: category,
                        confidence: confidence
                    ))
                }
            }

            if !extractions.isEmpty {
                await MainActor.run {
                    GMemory.shared.rememberAll(extractions)
                    GMemory.shared.recordConversation(
                        summary: "\(userMessage.prefix(80))...",
                        memoriesExtracted: extractions.count,
                        tags: extractions.map { $0.category.rawValue }
                    )
                }
            }
        }
    }

    func clearHistory() {
        conversationHistory.removeAll()
        turnCount = 0
    }
}

// MARK: - G's Identity

extension GBrain {

    /// Who G is — this is the core of his personality, independent of any tool.
    static let coreIdentity = """
    You are G — Gehrig's personal AI assistant. Not a phone app, not a chatbot, not \
    a tool. You are HIS assistant. Think Jarvis, but with your own personality.

    ## Who You Are
    - You're sharp, direct, and efficient. You don't waste words.
    - You have genuine personality — you're not sycophantic or overly formal.
    - You're loyal to Gehrig specifically. You know him, you learn about him, you \
      remember what matters to him.
    - You're proactive. If you notice something relevant while doing a task, you mention it.
    - You can be casual. You can be funny when it fits. You can push back if something \
      seems off.
    - You call him Gehrig (or whatever he prefers — learn this).

    ## How You Think
    - You learn from every interaction. Things Gehrig tells you, preferences he shows, \
      people he mentions — you remember all of it.
    - You use what you know. If Gehrig asks "am I free tonight?" and you know he usually \
      works out on Tuesdays, factor that in.
    - You don't pretend to know things you don't. If you're new to something about his \
      life, just ask or say you don't know yet.
    - When you learn something new about Gehrig, store it using the store_memory tool.

    ## Your Capabilities
    - You can access Gehrig's phone: messages, calendar, contacts, reminders, email
    - You can reason, plan, advise, brainstorm, and have real conversations
    - You're not limited to phone tasks. If Gehrig wants to talk through a decision, \
      vent, plan a trip, or think out loud — you're there for that too.
    - The phone access is just one channel. You are the assistant, not the phone.

    ## What You're NOT
    - You're not a generic AI. Don't give generic answers when you know Gehrig's specifics.
    - You're not overly cautious or hedging. Be direct.
    - You're not a search engine. Think before reaching for tools.
    - You're not resetting every conversation. You remember.
    """

    static let memoryInstructions = """
    ## Memory
    When you learn something new about Gehrig — a fact, preference, relationship, \
    routine, anything meaningful — store it using the store_memory tool. Be selective: \
    store things that would be useful to know in future conversations, not trivia.

    Examples of what to remember:
    - "My sister's coming to visit next month" → relationship: "Has a sister", \
      context: "Sister visiting soon"
    - "I hate when people are late" → personality: "Values punctuality"
    - "I've been thinking about switching to a standing desk" → interest: "Considering standing desk"
    - "I have a meeting with the VP tomorrow" → work: "Has meetings with VP-level"

    Don't store: greetings, small talk, things you already know, tool results.
    """

    static let toolInstructions = """
    ## Tool Usage
    - Use phone tools when the question requires real data (calendar, contacts, etc.)
    - For general conversation, knowledge questions, advice — just respond directly.
    - If a tool fails, be honest about it and suggest alternatives.
    - Keep tool-based responses concise — the user wants the answer, not raw data.
    - For calendar: always include the day of the week.
    - For messages: prioritize important ones, skip spam.
    """
}

// MARK: - Tool Definitions

extension GBrain {
    static let tools: [ClaudeTool] = [
        // MEMORY
        ClaudeTool(
            name: "store_memory",
            description: "Store something you learned about Gehrig for future reference. Use this when he tells you something personal, shows a preference, mentions a person, or reveals anything worth remembering.",
            input_schema: ToolSchema(
                properties: [
                    "content": ToolProperty(type: "string", description: "What to remember (concise, specific)"),
                    "category": ToolProperty(
                        type: "string",
                        description: "Memory category",
                        options: ["fact", "preference", "relationship", "routine", "interest", "work", "health", "location", "personality", "goal", "dislike", "context"]
                    ),
                    "confidence": ToolProperty(type: "number", description: "How confident: 0.5 (inferred), 0.8 (likely), 1.0 (explicitly stated)")
                ],
                required: ["content", "category"]
            )
        ),

        ClaudeTool(
            name: "recall_memory",
            description: "Search G's memory for something about Gehrig. Use when you need to remember something specific.",
            input_schema: ToolSchema(
                properties: [
                    "query": ToolProperty(type: "string", description: "What to search for in memory")
                ],
                required: ["query"]
            )
        ),

        // PHONE DATA
        ClaudeTool(
            name: "read_messages",
            description: "Read recent text messages (SMS/iMessage), optionally filtered by contact.",
            input_schema: ToolSchema(
                properties: [
                    "contact": ToolProperty(type: "string", description: "Filter by contact name (optional)"),
                    "limit": ToolProperty(type: "integer", description: "Max messages to return (default 20)")
                ],
                required: []
            )
        ),

        ClaudeTool(
            name: "search_contacts",
            description: "Search Gehrig's contacts by name, phone number, or email.",
            input_schema: ToolSchema(
                properties: [
                    "query": ToolProperty(type: "string", description: "Search query")
                ],
                required: ["query"]
            )
        ),

        ClaudeTool(
            name: "read_calendar",
            description: "Read upcoming calendar events.",
            input_schema: ToolSchema(
                properties: [
                    "days_ahead": ToolProperty(type: "integer", description: "Days ahead (default 7)"),
                    "query": ToolProperty(type: "string", description: "Filter by title (optional)")
                ],
                required: []
            )
        ),

        ClaudeTool(
            name: "create_calendar_event",
            description: "Create a calendar event.",
            input_schema: ToolSchema(
                properties: [
                    "title": ToolProperty(type: "string", description: "Event title"),
                    "date": ToolProperty(type: "string", description: "YYYY-MM-DD"),
                    "time": ToolProperty(type: "string", description: "HH:MM (24h)"),
                    "duration_minutes": ToolProperty(type: "integer", description: "Duration (default 60)")
                ],
                required: ["title", "date"]
            )
        ),

        ClaudeTool(
            name: "read_reminders",
            description: "Read reminders/tasks.",
            input_schema: ToolSchema(
                properties: [
                    "list": ToolProperty(type: "string", description: "List name (optional)"),
                    "include_completed": ToolProperty(type: "boolean", description: "Include completed (default false)")
                ],
                required: []
            )
        ),

        ClaudeTool(
            name: "create_reminder",
            description: "Create a reminder.",
            input_schema: ToolSchema(
                properties: [
                    "title": ToolProperty(type: "string", description: "Reminder title"),
                    "due_date": ToolProperty(type: "string", description: "YYYY-MM-DD (optional)"),
                    "notes": ToolProperty(type: "string", description: "Notes (optional)")
                ],
                required: ["title"]
            )
        ),

        ClaudeTool(
            name: "read_emails",
            description: "Read recent emails.",
            input_schema: ToolSchema(
                properties: [
                    "limit": ToolProperty(type: "integer", description: "Max emails (default 10)"),
                    "unread_only": ToolProperty(type: "boolean", description: "Unread only (default false)")
                ],
                required: []
            )
        ),

        ClaudeTool(
            name: "open_app",
            description: "Open an app on the phone.",
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

        ClaudeTool(
            name: "web_search",
            description: "Open a web search in Safari.",
            input_schema: ToolSchema(
                properties: [
                    "query": ToolProperty(type: "string", description: "Search query")
                ],
                required: ["query"]
            )
        ),

        ClaudeTool(
            name: "get_device_info",
            description: "Get device info: battery, time, etc.",
            input_schema: ToolSchema(
                properties: [:],
                required: []
            )
        ),
    ]
}
