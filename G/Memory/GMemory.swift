import Foundation

/// G's long-term memory. This is how G learns about Gehrig over time.
///
/// Every conversation, G can extract and store:
/// - Facts ("Gehrig works at X", "his mom's name is Y")
/// - Preferences ("he likes his coffee black", "prefers morning meetings")
/// - Relationships ("Sarah is his girlfriend", "Jake is his coworker")
/// - Routines ("usually works out at 6am", "checks email first thing")
/// - Past interactions ("last week he asked about flights to NYC")
///
/// Memory is stored locally on device as JSON files. Nothing leaves the phone
/// except what gets sent to Claude in the conversation context.
class GMemory: ObservableObject {
    static let shared = GMemory()

    // MARK: - Storage

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// All stored memories
    @Published private(set) var memories: [Memory] = []

    /// The user profile — synthesized from memories
    @Published private(set) var profile: UserProfile

    /// Recent conversation summaries (not full transcripts, just key points)
    @Published private(set) var conversationSummaries: [ConversationSummary] = []

    // MARK: - Data Types

    struct Memory: Codable, Identifiable, Equatable {
        let id: UUID
        let category: MemoryCategory
        let content: String
        let confidence: Double      // 0.0–1.0, how sure G is about this
        let source: String          // "conversation", "calendar", "contacts", etc.
        let createdAt: Date
        var lastReferencedAt: Date  // updated when G uses this memory
        var referenceCount: Int     // how often this comes up

        init(category: MemoryCategory, content: String, confidence: Double = 0.8, source: String = "conversation") {
            self.id = UUID()
            self.category = category
            self.content = content
            self.confidence = confidence
            self.source = source
            self.createdAt = Date()
            self.lastReferencedAt = Date()
            self.referenceCount = 1
        }
    }

    enum MemoryCategory: String, Codable, CaseIterable {
        case fact           // "Works as a software engineer"
        case preference     // "Prefers dark mode everything"
        case relationship   // "Sarah - girlfriend, lives in Austin"
        case routine        // "Gym at 6am on weekdays"
        case interest       // "Into basketball, tech, investing"
        case work           // "Works at [company], role is [X]"
        case health         // "Allergic to shellfish"
        case location       // "Lives in Austin, TX"
        case personality    // "Direct communicator, doesn't like small talk"
        case goal           // "Wants to learn Spanish this year"
        case dislike        // "Hates being called 'buddy'"
        case context        // Temporary/situational: "traveling this week"
    }

    struct UserProfile: Codable {
        var name: String
        var summary: String                        // 2-3 sentence bio G has built
        var topFacts: [String]                     // most important/referenced facts
        var lastUpdated: Date

        static let initial = UserProfile(
            name: "Gehrig",
            summary: "",
            topFacts: [],
            lastUpdated: Date()
        )
    }

    struct ConversationSummary: Codable, Identifiable {
        let id: UUID
        let date: Date
        let summary: String          // 1-2 sentence summary of the conversation
        let memoriesExtracted: Int   // how many new memories came from this
        let topicTags: [String]      // ["calendar", "work", "personal"]

        init(summary: String, memoriesExtracted: Int = 0, topicTags: [String] = []) {
            self.id = UUID()
            self.date = Date()
            self.summary = summary
            self.memoriesExtracted = memoriesExtracted
            self.topicTags = topicTags
        }
    }

    // MARK: - Init

    private init() {
        self.profile = .initial
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    // MARK: - Public API

    /// Store a new memory. Deduplicates against existing memories.
    func remember(_ content: String, category: MemoryCategory, confidence: Double = 0.8, source: String = "conversation") {
        // Check for duplicates or updates
        if let existing = memories.firstIndex(where: {
            $0.category == category && contentsSimilar($0.content, content)
        }) {
            // Update existing memory
            memories[existing].lastReferencedAt = Date()
            memories[existing].referenceCount += 1
        } else {
            let memory = Memory(
                category: category,
                content: content,
                confidence: confidence,
                source: source
            )
            memories.append(memory)
        }
        save()
    }

    /// Store multiple memories at once (typically after Claude extracts them).
    func rememberAll(_ newMemories: [MemoryExtraction]) {
        for extraction in newMemories {
            remember(
                extraction.content,
                category: extraction.category,
                confidence: extraction.confidence,
                source: extraction.source
            )
        }
        updateProfile()
    }

    /// Record a conversation summary.
    func recordConversation(summary: String, memoriesExtracted: Int, tags: [String]) {
        let entry = ConversationSummary(
            summary: summary,
            memoriesExtracted: memoriesExtracted,
            topicTags: tags
        )
        conversationSummaries.insert(entry, at: 0)

        // Keep last 100 summaries
        if conversationSummaries.count > 100 {
            conversationSummaries = Array(conversationSummaries.prefix(100))
        }
        save()
    }

    /// Get memories relevant to a query (simple keyword match for now).
    func recall(query: String) -> [Memory] {
        let keywords = query.lowercased().split(separator: " ").map(String.init)
        return memories
            .filter { memory in
                let content = memory.content.lowercased()
                return keywords.contains(where: { content.contains($0) })
            }
            .sorted { $0.referenceCount > $1.referenceCount }
    }

    /// Get all memories formatted as context for Claude.
    func getContextForAI() -> String {
        if memories.isEmpty && profile.summary.isEmpty {
            return """
            [MEMORY: G doesn't know much about Gehrig yet. Learn from this conversation.]
            """
        }

        var parts: [String] = []

        // Profile summary
        if !profile.summary.isEmpty {
            parts.append("ABOUT GEHRIG: \(profile.summary)")
        }

        // Key facts by category (most referenced first)
        let grouped = Dictionary(grouping: memories) { $0.category }
        let sortedCategories: [MemoryCategory] = [
            .fact, .relationship, .work, .preference, .routine,
            .interest, .goal, .personality, .location, .health,
            .dislike, .context
        ]

        for category in sortedCategories {
            guard let categoryMemories = grouped[category], !categoryMemories.isEmpty else { continue }
            let sorted = categoryMemories.sorted { $0.referenceCount > $1.referenceCount }
            let items = sorted.prefix(10).map { "- \($0.content)" }.joined(separator: "\n")
            parts.append("\(category.rawValue.uppercased()):\n\(items)")
        }

        // Recent conversation context
        let recentConvos = conversationSummaries.prefix(5)
        if !recentConvos.isEmpty {
            let convoLines = recentConvos.map { summary in
                let daysAgo = Calendar.current.dateComponents([.day], from: summary.date, to: Date()).day ?? 0
                let timeRef = daysAgo == 0 ? "Today" : daysAgo == 1 ? "Yesterday" : "\(daysAgo) days ago"
                return "- \(timeRef): \(summary.summary)"
            }.joined(separator: "\n")
            parts.append("RECENT CONVERSATIONS:\n\(convoLines)")
        }

        return parts.joined(separator: "\n\n")
    }

    /// Get a compact memory count summary.
    var stats: String {
        "\(memories.count) memories, \(conversationSummaries.count) conversations"
    }

    /// Forget a specific memory.
    func forget(_ id: UUID) {
        memories.removeAll { $0.id == id }
        save()
    }

    /// Clear all memories (nuclear option).
    func forgetEverything() {
        memories.removeAll()
        conversationSummaries.removeAll()
        profile = .initial
        save()
    }

    // MARK: - Profile Synthesis

    /// Rebuild the user profile from memories.
    func updateProfile() {
        // Top facts: most referenced memories
        let topMemories = memories
            .sorted { $0.referenceCount > $1.referenceCount }
            .prefix(8)
            .map { $0.content }
        profile.topFacts = Array(topMemories)

        // Build summary from key categories
        var summaryParts: [String] = [profile.name]
        if let work = memories.first(where: { $0.category == .work }) {
            summaryParts.append(work.content)
        }
        if let location = memories.first(where: { $0.category == .location }) {
            summaryParts.append(location.content)
        }

        if summaryParts.count > 1 {
            profile.summary = summaryParts.joined(separator: ". ") + "."
        }
        profile.lastUpdated = Date()
        save()
    }

    // MARK: - Similarity Check

    private func contentsSimilar(_ a: String, _ b: String) -> Bool {
        let wordsA = Set(a.lowercased().split(separator: " "))
        let wordsB = Set(b.lowercased().split(separator: " "))
        let intersection = wordsA.intersection(wordsB)
        let union = wordsA.union(wordsB)
        guard !union.isEmpty else { return true }
        let similarity = Double(intersection.count) / Double(union.count)
        return similarity > 0.6
    }

    // MARK: - Persistence

    private var storageURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("g_memory")
    }

    private func save() {
        let dir = storageURL
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        if let data = try? encoder.encode(memories) {
            try? data.write(to: dir.appendingPathComponent("memories.json"))
        }
        if let data = try? encoder.encode(profile) {
            try? data.write(to: dir.appendingPathComponent("profile.json"))
        }
        if let data = try? encoder.encode(conversationSummaries) {
            try? data.write(to: dir.appendingPathComponent("conversations.json"))
        }
    }

    private func load() {
        let dir = storageURL
        if let data = try? Data(contentsOf: dir.appendingPathComponent("memories.json")),
           let decoded = try? decoder.decode([Memory].self, from: data) {
            memories = decoded
        }
        if let data = try? Data(contentsOf: dir.appendingPathComponent("profile.json")),
           let decoded = try? decoder.decode(UserProfile.self, from: data) {
            profile = decoded
        }
        if let data = try? Data(contentsOf: dir.appendingPathComponent("conversations.json")),
           let decoded = try? decoder.decode([ConversationSummary].self, from: data) {
            conversationSummaries = decoded
        }
    }
}

// MARK: - Memory Extraction (from Claude)

struct MemoryExtraction: Codable {
    let content: String
    let category: GMemory.MemoryCategory
    let confidence: Double
    let source: String

    init(content: String, category: GMemory.MemoryCategory, confidence: Double = 0.8, source: String = "conversation") {
        self.content = content
        self.category = category
        self.confidence = confidence
        self.source = source
    }
}
