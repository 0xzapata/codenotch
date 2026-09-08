import Combine
import Foundation

/// Monitors active models running in memory on the local Ollama daemon (`http://127.0.0.1:11434`).
///
/// When an LLM is loaded or generating tokens in Ollama, feeds live `AgentSession` records
/// into Codenotch's inner activity ring.
@MainActor
final class OllamaActivityMonitor: ObservableObject, AgentActivityMonitor {
    @Published private(set) var sessions: [AgentSession] = []
    var sessionsPublisher: AnyPublisher<[AgentSession], Never> { $sessions.eraseToAnyPublisher() }

    private let endpoint: URL
    private let interval: TimeInterval
    private let session: URLSession
    private var timer: Timer?

    struct PSResponse: Decodable {
        let models: [LoadedModel]?
    }

    struct LoadedModel: Decodable {
        let name: String
        let model: String?
        let size: Int64?
        let sizeVram: Int64?
        let expiresAt: String?

        enum CodingKeys: String, CodingKey {
            case name, model, size
            case sizeVram = "size_vram"
            case expiresAt = "expires_at"
        }
    }

    init(
        endpoint: URL = URL(string: "http://127.0.0.1:11434/api/ps")!,
        interval: TimeInterval = 3,
        session: URLSession? = nil
    ) {
        self.endpoint = endpoint
        self.interval = interval
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 2
            self.session = URLSession(configuration: config)
        }
    }

    func start() {
        poll()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        Task { [weak self, endpoint, session] in
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 2
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    await self?.updateSessions([])
                    return
                }

                let parsed = try JSONDecoder().decode(PSResponse.self, from: data)
                let activeSessions = Self.sessions(from: parsed)
                await self?.updateSessions(activeSessions)
            } catch {
                await self?.updateSessions([])
            }
        }
    }

    /// Converts a PSResponse into AgentSession records.
    static func sessions(from response: PSResponse) -> [AgentSession] {
        guard let models = response.models else { return [] }
        return models.map { m in
            let isVram = (m.sizeVram ?? 0) > 0
            let bytes = (isVram ? m.sizeVram : nil) ?? m.size ?? 0
            return AgentSession(
                id: "ollama.\(m.name)",
                name: m.name,
                detail: formatMemory(bytes, isVram: isVram),
                state: .busy,
                waitingFor: nil,
                since: Date(),
                processID: nil
            )
        }
    }

    /// Formats bytes into a human-readable VRAM or memory size string.
    static func formatMemory(_ bytes: Int64, isVram: Bool = true) -> String {
        let label = isVram ? "VRAM" : "RAM"
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb >= 1.0 {
            return String(format: "%.1f GB %@", locale: Locale(identifier: "en_US_POSIX"), gb, label)
        }
        let mb = Double(bytes) / (1024 * 1024)
        return String(format: "%.0f MB %@", locale: Locale(identifier: "en_US_POSIX"), mb, label)
    }

    private func updateSessions(_ newSessions: [AgentSession]) {
        guard newSessions != sessions else { return }
        self.sessions = newSessions
    }
}
