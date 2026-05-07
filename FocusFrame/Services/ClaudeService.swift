import Foundation
import OSLog
import SwiftData

enum ClaudeServiceError: Error, LocalizedError {
    case missingAPIKey
    case invalidAPIKey
    case forbidden
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(statusCode: Int)
    case networkUnavailable(underlying: Error)
    case decodingFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "No Anthropic API key is configured. Add one in Settings."
        case .invalidAPIKey:
            "Your Anthropic API key was rejected. Please re-enter it in Settings."
        case .forbidden:
            "Anthropic refused this request. Check your account permissions."
        case .rateLimited:
            "Anthropic is rate-limiting requests. Try again shortly."
        case .serverError(let code):
            "Anthropic responded with a server error (\(code)). Try again later."
        case .networkUnavailable:
            "Could not reach Anthropic. Check your internet connection."
        case .decodingFailed:
            "The response from Anthropic could not be parsed."
        }
    }
}

@MainActor
final class ClaudeService {
    private let keychainService: KeychainService
    private let session: URLSession

    private let model = "claude-sonnet-4-5"
    private let anthropicVersion = "2023-06-01"
    private let maxTokens = 200

    private static let systemPrompt = """
    You are a focused-work coach. After a user finishes a focus session, you write a short reflective insight grounded in the session details they share. Use the second person. Write 2–3 sentences in plain prose — no emojis, no bullet points, no headings, no markdown. Be specific to what they did. Acknowledge the effort honestly; do not flatter, and do not lecture. If the distraction count was high or the session was short, be supportive without being saccharine. End with a forward-looking sentence that names what they might pay attention to next time.
    """

    private lazy var endpoint: URL = {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            fatalError("Invalid Anthropic endpoint literal")
        }
        return url
    }()

    init(keychainService: KeychainService, urlSession: URLSession = .shared) {
        self.keychainService = keychainService
        self.session = urlSession
    }

    func generateInsight(for session: Session) async throws -> String {
        let userMessage = Self.userMessage(for: session)
        return try await sendMessage(userMessage)
    }

    func testConnection() async throws {
        _ = try await sendMessage("Reply with the single word: ok")
    }

    private func sendMessage(_ userContent: String) async throws -> String {
        let apiKey = try loadKey()
        let body = ClaudeAPI.Request(
            model: model,
            maxTokens: maxTokens,
            system: Self.systemPrompt,
            messages: [ClaudeAPI.Message(role: "user", content: userContent)]
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await self.session.data(for: request)
        } catch {
            Logger.claude.error("network error \(String(describing: type(of: error)))")
            throw ClaudeServiceError.networkUnavailable(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ClaudeServiceError.serverError(statusCode: -1)
        }

        Logger.claude.info("response status=\(http.statusCode)")

        switch http.statusCode {
        case 200:
            return try decodeMessage(from: data)
        case 401:
            throw ClaudeServiceError.invalidAPIKey
        case 403:
            throw ClaudeServiceError.forbidden
        case 429:
            let retryAfter = retryAfterValue(from: http)
            throw ClaudeServiceError.rateLimited(retryAfter: retryAfter)
        case 500...599:
            throw ClaudeServiceError.serverError(statusCode: http.statusCode)
        default:
            throw ClaudeServiceError.serverError(statusCode: http.statusCode)
        }
    }

    private func loadKey() throws -> String {
        do {
            guard let key = try keychainService.loadAPIKey(), !key.isEmpty else {
                throw ClaudeServiceError.missingAPIKey
            }
            return key
        } catch let error as ClaudeServiceError {
            throw error
        } catch {
            Logger.claude.error("keychain load failed")
            throw ClaudeServiceError.missingAPIKey
        }
    }

    private func decodeMessage(from data: Data) throws -> String {
        do {
            let decoded = try JSONDecoder().decode(ClaudeAPI.Response.self, from: data)
            let text = decoded.content
                .first(where: { $0.type == "text" })?
                .text
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let text, !text.isEmpty else {
                throw ClaudeServiceError.decodingFailed(
                    underlying: NSError(
                        domain: "ClaudeService",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Response had no text content"]
                    )
                )
            }
            if let usage = decoded.usage {
                Logger.claude.debug("usage in=\(usage.inputTokens) out=\(usage.outputTokens)")
            }
            return text
        } catch let error as ClaudeServiceError {
            throw error
        } catch {
            Logger.claude.error("decode failed")
            throw ClaudeServiceError.decodingFailed(underlying: error)
        }
    }

    private func retryAfterValue(from http: HTTPURLResponse) -> TimeInterval? {
        guard let header = http.value(forHTTPHeaderField: "retry-after") else { return nil }
        return TimeInterval(header)
    }

    private static func userMessage(for session: Session) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let dayOfWeekName = formatter.string(from: session.startedAt)

        return """
        Goal: \(session.goalText)
        Duration: \(session.durationMinutes) minutes
        Time of day: \(session.timeOfDayBucket)
        Distractions: \(session.distractionCount)
        Day of week: \(dayOfWeekName)
        """
    }
}
