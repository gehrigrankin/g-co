import Foundation

// MARK: - Conversation

struct ConversationMessage: Identifiable, Equatable {
    let id = UUID()
    let role: MessageRole
    let text: String
    let action: String?      // e.g. "Checking your messages..."
    let timestamp: Date

    init(role: MessageRole, text: String, action: String? = nil) {
        self.role = role
        self.text = text
        self.action = action
        self.timestamp = Date()
    }
}

enum MessageRole: Equatable {
    case user
    case assistant
}

// MARK: - Claude API

struct ClaudeRequest: Encodable {
    let model: String = "claude-sonnet-4-20250514"
    let max_tokens: Int = 4096
    let system: String
    let messages: [ClaudeMessage]
    let tools: [ClaudeTool]?
}

struct ClaudeMessage: Codable {
    let role: String
    let content: ClaudeContent

    init(role: String, text: String) {
        self.role = role
        self.content = .text(text)
    }

    init(role: String, blocks: [ClaudeContentBlock]) {
        self.role = role
        self.content = .blocks(blocks)
    }
}

enum ClaudeContent: Codable {
    case text(String)
    case blocks([ClaudeContentBlock])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let str):
            try container.encode(str)
        case .blocks(let blocks):
            try container.encode(blocks)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .text(str)
        } else {
            let blocks = try container.decode([ClaudeContentBlock].self)
            self = .blocks(blocks)
        }
    }
}

struct ClaudeContentBlock: Codable {
    let type: String
    let text: String?
    let id: String?
    let name: String?
    let input: [String: AnyCodable]?

    init(type: String, text: String) {
        self.type = type
        self.text = text
        self.id = nil
        self.name = nil
        self.input = nil
    }

    init(toolResult id: String, content: String) {
        self.type = "tool_result"
        self.text = nil
        self.id = id
        self.name = nil
        self.input = nil
        // Note: tool_result has a different structure, handled in encoding
    }
}

struct ClaudeTool: Encodable {
    let name: String
    let description: String
    let input_schema: ToolSchema
}

struct ToolSchema: Encodable {
    let type: String = "object"
    let properties: [String: ToolProperty]
    let required: [String]
}

struct ToolProperty: Encodable {
    let type: String
    let description: String
    let `enum`: [String]?

    init(type: String, description: String, options: [String]? = nil) {
        self.type = type
        self.description = description
        self.enum = options
    }
}

struct ClaudeResponse: Decodable {
    let id: String
    let type: String
    let content: [ResponseBlock]
    let stop_reason: String?
}

struct ResponseBlock: Decodable {
    let type: String
    let text: String?
    let id: String?
    let name: String?
    let input: [String: AnyCodable]?
}

struct ToolResultMessage: Encodable {
    let role: String = "user"
    let content: [ToolResultContent]
}

struct ToolResultContent: Encodable {
    let type: String = "tool_result"
    let tool_use_id: String
    let content: String
}

// MARK: - AnyCodable (for dynamic JSON)

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) { value = str }
        else if let int = try? container.decode(Int.self) { value = int }
        else if let double = try? container.decode(Double.self) { value = double }
        else if let bool = try? container.decode(Bool.self) { value = bool }
        else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        }
        else if let arr = try? container.decode([AnyCodable].self) {
            value = arr.map { $0.value }
        }
        else { value = NSNull() }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let str as String: try container.encode(str)
        case let int as Int: try container.encode(int)
        case let double as Double: try container.encode(double)
        case let bool as Bool: try container.encode(bool)
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        case let arr as [Any]:
            try container.encode(arr.map { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }

    var stringValue: String? { value as? String }
    var intValue: Int? { value as? Int }
    var boolValue: Bool? { value as? Bool }
}
