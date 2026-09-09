import AppKit
import Foundation
import os

/// Monitors local models running in Ollama (`http://127.0.0.1:11434`).
///
/// When models are loaded in memory/VRAM, displays the active model(s),
/// VRAM allocation, and the keep-alive unload countdown.
/// When Ollama is idle (running with no models in memory), displays an idle ring.
/// If Ollama is not installed on this Mac, no cell is drawn.
actor OllamaLocalProvider: UsageProvider {
    nonisolated let id = "ollama-local"
    nonisolated let displayName = "Ollama (Local)"
    nonisolated let glyph = ProviderGlyph.ollamaLocal
    nonisolated var isVisibleWhenAbsent: Bool { false }

    private let endpoint = URL(string: "http://127.0.0.1:11434/api/ps")!
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 2
            config.timeoutIntervalForResource = 3
            self.session = URLSession(configuration: config)
        }
    }

    /// Checks if the Ollama application or local daemon is actively running.
    static func isDaemonRunning() -> Bool {
        // Fast path 1: check if Ollama macOS app is running
        if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.electron.ollama").isEmpty {
            return true
        }

        // Fast path 2: check if daemon is listening on 127.0.0.1:11434 (e.g. CLI ollama serve)
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(11434).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        var tv = timeval(tv_sec: 0, tv_usec: 50_000) // 50ms timeout
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    nonisolated var signInRoute: SignInRoute {
        .openApp(bundleID: "com.electron.ollama", name: "Ollama")
    }

    nonisolated func account() -> ProviderAccount? {
        guard Self.isDaemonRunning() else { return nil }

        return ProviderAccount(
            label: "Localhost",
            plan: "Local",
            source: "Ollama",
            manageURL: URL(string: "http://127.0.0.1:11434")
        )
    }

    nonisolated func forgetCachedCredential() {}

    nonisolated func signOut() async {}

    nonisolated func presentSignIn() {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.electron.ollama") {
            NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
        } else if FileManager.default.fileExists(atPath: "/Applications/Ollama.app") {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Ollama.app"))
        }
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        guard Self.isDaemonRunning() else {
            throw UsageProviderError.needsAuth
        }

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 2

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // Daemon is offline or unreachable; present needsAuth so it prompts to start Ollama
            throw UsageProviderError.needsAuth
        }

        guard let http = response as? HTTPURLResponse else {
            throw UsageProviderError.badResponse(status: -1)
        }

        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw UsageProviderError.needsAuth
            }
            throw UsageProviderError.badResponse(status: http.statusCode)
        }

        let windows = try OllamaLocalUsage.windows(from: data)
        return ProviderSnapshot(
            id: id,
            displayName: displayName,
            glyph: glyph,
            fidelity: .official,
            status: .ok,
            windows: windows,
            headlineID: windows.first?.id
        )
    }
}
