import Foundation

enum ClaudeAPI {
    struct Request: Encodable {
        let model: String
        let maxTokens: Int
        let system: String
        let messages: [Message]

        enum CodingKeys: String, CodingKey {
            case model
            case maxTokens = "max_tokens"
            case system
            case messages
        }
    }

    struct Message: Codable {
        let role: String
        let content: String
    }

    struct Response: Decodable {
        let id: String
        let model: String
        let content: [ContentBlock]
        let stopReason: String?
        let usage: Usage?

        enum CodingKeys: String, CodingKey {
            case id, model, content
            case stopReason = "stop_reason"
            case usage
        }
    }

    struct ContentBlock: Decodable {
        let type: String
        let text: String
    }

    struct Usage: Decodable {
        let inputTokens: Int
        let outputTokens: Int

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }
}
